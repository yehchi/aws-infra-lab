# ============================================================
# RDS Module
# PostgreSQL 資料庫 + Secrets Manager（密碼不寫死在任何地方）
# ============================================================

# ----- 隨機產生 DB 密碼 -----
# 密碼由 Terraform 自動產生，不需要人手動設定
resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ----- Secrets Manager -----
# 把 DB 連線資訊存到 Secrets Manager，ECS 啟動時動態讀取
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}-${var.environment}-db-credentials"
  description             = "RDS PostgreSQL credentials for ${var.project_name}"
  recovery_window_in_days = 0 # dev 環境不需要等待期，可立即刪除

  tags = {
    Name = "${var.project_name}-${var.environment}-db-credentials"
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
  })
}

# ----- RDS Subnet Group -----
# 告訴 RDS 要放在哪些 Subnet（Private Subnet）
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# ----- RDS PostgreSQL -----
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-db"

  # 引擎設定
  engine         = "postgres"
  engine_version = "16.15"
  instance_class = var.db_instance_class # dev: db.t3.micro

  # 儲存
  allocated_storage     = 20
  max_allocated_storage = 50 # 自動擴展上限
  storage_type          = "gp3"
  storage_encrypted     = true # 加密儲存，金融業合規要求

  # 資料庫設定
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  # 網路設定
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = false # 不對外，只有 ECS 能連

  # 備份設定
  backup_retention_period = 7     # 保留 7 天備份
  backup_window           = "03:00-04:00" # UTC 凌晨 3 點（台灣早上 11 點）
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Dev 環境設定
  multi_az            = false # dev 不需要 Multi-AZ，省錢
  skip_final_snapshot = true  # destroy 時不需要最終快照
  deletion_protection = false # dev 允許直接刪除

  tags = {
    Name = "${var.project_name}-${var.environment}-db"
  }
}
