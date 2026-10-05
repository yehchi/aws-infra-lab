# ============================================================
# VPC Module
# 建立整個網路基礎：VPC、Subnet、IGW、NAT、Route Table
# ============================================================

# ----- VPC -----
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# ----- Internet Gateway -----
# 讓 Public Subnet 可以連到網際網路
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# ----- Public Subnets (x2 AZ) -----
# 放 ALB 用，需要對外接受流量
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-${var.availability_zones[count.index]}"
  }
}

# ----- Private Subnets (x2 AZ) -----
# 放 ECS Fargate 和 RDS，不暴露公網
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-${var.availability_zones[count.index]}"
  }
}

# ----- Public Route Table -----
# Public Subnet 的流量走 Internet Gateway 出去
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ----- NAT Instance -----
# 讓 Private Subnet 的服務（ECS）可以連外網（拉 image、呼叫 AWS API）
# 用 NAT Instance 而非 NAT Gateway，月費從 $30-40 降到 ~$5
# 使用 fck-nat AMI（社群維護的輕量 NAT Instance）

data "aws_ami" "fck_nat" {
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

resource "aws_instance" "nat" {
  ami                    = data.aws_ami.fck_nat.id
  instance_type          = "t4g.nano" # ARM 架構，最便宜的選項 ~$3/月
  subnet_id              = aws_subnet.public[0].id
  source_dest_check      = false # NAT 必須關閉此檢查
  vpc_security_group_ids = [aws_security_group.nat.id]

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-instance"
  }
}

# NAT Instance 的 Security Group
resource "aws_security_group" "nat" {
  name_prefix = "${var.project_name}-${var.environment}-nat-"
  description = "Security group for NAT instance"
  vpc_id      = aws_vpc.main.id

  # 允許 Private Subnet 的流量通過
  ingress {
    description = "Allow all traffic from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.private_subnet_cidrs
  }

  # 允許對外
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-sg"
  }
}

# ----- Private Route Table -----
# Private Subnet 的流量走 NAT Instance 出去
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
