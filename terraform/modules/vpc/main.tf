# ============================================================
# VPC Module — 三層式網路架構
#
#   Public   ：ALB、NAT（唯一能直接對外的一層）
#   App      ：ECS Fargate（只能經 NAT 主動對外，外部連不進來）
#   Database ：RDS（route table 沒有任何對外路由，連 NAT 都不給）
#
# 資料庫獨立一層的理由：即使應用層被入侵，資料庫所在網段也沒有
# 任何路徑能把資料直接送出 VPC，符合金融業網段隔離要求。
#
# NAT 模式（var.nat_mode）：
#   instance：1 台 NAT Instance（dev，成本優先，接受單點故障）
#   gateway ：每個 AZ 各 1 台 NAT Gateway（prod，可用性優先）
# ============================================================

locals {
  az_count     = length(var.availability_zones)
  use_nat_inst = var.nat_mode == "instance"
  use_nat_gw   = var.nat_mode == "gateway"
  name_prefix  = "${var.project_name}-${var.environment}"
}

# ----- VPC -----
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# ----- Internet Gateway -----
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# ============================================================
# Subnets（每層各跨 2 個 AZ）
# ============================================================

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "app" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.name_prefix}-app-${var.availability_zones[count.index]}"
    Tier = "app"
  }
}

resource "aws_subnet" "database" {
  count = local.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.name_prefix}-db-${var.availability_zones[count.index]}"
    Tier = "database"
  }
}

# ============================================================
# Public Route Table：0.0.0.0/0 → Internet Gateway
# ============================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# NAT：二選一
# ============================================================

# ----- 模式 A：NAT Instance（dev）-----
# fck-nat：社群維護的輕量 NAT AMI，t4g.nano 月費約 $3（NAT Gateway 約 $30-40 + 流量費）
data "aws_ami" "fck_nat" {
  count = local.use_nat_inst ? 1 : 0

  most_recent = true
  owners      = ["568608671756"] # fck-nat 官方 AMI owner

  filter {
    name   = "name"
    values = ["fck-nat-al2023-*-arm64-ebs"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

resource "aws_security_group" "nat" {
  count = local.use_nat_inst ? 1 : 0

  name_prefix = "${local.name_prefix}-nat-"
  description = "Security group for NAT instance"
  vpc_id      = aws_vpc.main.id

  # 只接受 App 層的流量（Database 層沒有走 NAT 的路由，也不在允許清單）
  ingress {
    description = "Allow all traffic from app subnets"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.app_subnet_cidrs
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-nat-sg"
  }
}

resource "aws_instance" "nat" {
  count = local.use_nat_inst ? 1 : 0

  ami                    = data.aws_ami.fck_nat[0].id
  instance_type          = "t4g.nano"
  subnet_id              = aws_subnet.public[0].id
  source_dest_check      = false # NAT 必須關閉此檢查，才能轉送不是給自己的封包
  vpc_security_group_ids = [aws_security_group.nat[0].id]

  tags = {
    Name = "${local.name_prefix}-nat-instance"
  }
}

# ----- 模式 B：每個 AZ 一台 NAT Gateway（prod）-----
# 某個 AZ 故障時，另一個 AZ 的 App 層仍可透過自己 AZ 的 NAT 對外
resource "aws_eip" "nat" {
  count = local.use_nat_gw ? local.az_count : 0

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-${var.availability_zones[count.index]}"
  }
}

resource "aws_nat_gateway" "main" {
  count = local.use_nat_gw ? local.az_count : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${local.name_prefix}-natgw-${var.availability_zones[count.index]}"
  }

  depends_on = [aws_internet_gateway.main]
}

# ============================================================
# App Route Tables：每個 AZ 一張，0.0.0.0/0 → NAT
# （每 AZ 一張，prod 時才能各自指向同 AZ 的 NAT Gateway）
# ============================================================

resource "aws_route_table" "app" {
  count = local.az_count

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-app-rt-${var.availability_zones[count.index]}"
  }
}

resource "aws_route" "app_via_nat_instance" {
  count = local.use_nat_inst ? local.az_count : 0

  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat[0].primary_network_interface_id
}

resource "aws_route" "app_via_nat_gateway" {
  count = local.use_nat_gw ? local.az_count : 0

  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

resource "aws_route_table_association" "app" {
  count = local.az_count

  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# ============================================================
# Database Route Table：刻意不加任何 route
# 只剩 AWS 預設的 VPC 內部路由（local），資料庫無法對外連線
# ============================================================

resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-db-rt"
  }
}

resource "aws_route_table_association" "database" {
  count = local.az_count

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}
