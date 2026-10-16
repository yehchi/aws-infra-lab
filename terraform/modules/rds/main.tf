# ============================================================
# RDS Module
# PostgreSQL 資料庫 + Secrets Manager（密碼不寫死在任何地方）
#
# dev / prod 差異全部由變數控制（見 variables.tf）：
#   multi_az、deletion_protection、skip_final_snapshot、backup_retention_days
# ============================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ----- 隨機產生 DB 密碼 -----
# 密碼由 Terraform 自動產生，不經過任何人的手
resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ----- Secrets Manager -----
# DB 連線資訊存在這裡，ECS 啟動時動態注入，程式碼與設定檔都不含密碼
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.name_prefix}-db-credentials"
  description             = "RDS PostgreSQL credentials for ${local.name_prefix}"
  recovery_window_in_days = var.secret_recovery_window_days

  tags = {
    Name = "${local.name_prefix}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    host     = aws_db_instance.main.address
    port     = 5432
    dbname   = var.db_name
    # 讀取用 endpoint：有 Read Replica 就指向複本，沒有就指向主庫
    # 應用程式一律讀這個值，dev / prod 程式碼完全相同
    read_host = var.create_read_replica ? aws_db_instance.replica[0].address : aws_db_instance.main.address
  })
}

# ----- RDS Subnet Group -----
# 只放在 Database 層 subnet（無對外路由），跨 2 個 AZ
# Multi-AZ 時，Standby 會自動建在另一個 AZ 的 subnet
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet"
  subnet_ids = var.db_subnet_ids

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

# ----- RDS PostgreSQL -----
resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-db"

  # 引擎
  engine         = "postgres"
  engine_version = "16.15"
  instance_class = var.db_instance_class

  # 儲存
  allocated_storage     = 20
  max_allocated_storage = 50 # 儲存空間自動擴展上限
  storage_type          = "gp3"
  storage_encrypted     = true # 靜態加密

  # 資料庫
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  # 網路
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false

  # 可用性：Multi-AZ 會在另一個 AZ 維持一台同步複寫的 Standby，主機故障時自動切換
  multi_az = var.multi_az

  # 備份與維護
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00" # UTC（台灣 11:00-12:00，非交易時段的低峰）
  maintenance_window      = "Mon:04:00-Mon:05:00"
  apply_immediately       = var.apply_immediately

  # 刪除保護
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-db-final"

  tags = {
    Name = "${local.name_prefix}-db"
  }
}

# ----- Read Replica（讀寫分離）-----
# 主庫非同步複製到這台唯讀複本：查詢與批次報表讀這裡，寫入仍走主庫
# 跟 Multi-AZ 的 Standby 不同：Standby 只待命、不能讀；Replica 可以分擔讀取
resource "aws_db_instance" "replica" {
  count = var.create_read_replica ? 1 : 0

  identifier          = "${local.name_prefix}-db-replica"
  replicate_source_db = aws_db_instance.main.identifier # 同區域複本：subnet group 與加密設定沿用主庫
  instance_class      = var.db_instance_class
  storage_type        = "gp3"
  storage_encrypted   = true

  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false

  multi_az                = false # 複本本身不做 Multi-AZ；主庫已有 Standby
  backup_retention_period = 0     # 複本不另外備份
  apply_immediately       = true
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = true

  tags = {
    Name = "${local.name_prefix}-db-replica"
  }
}
