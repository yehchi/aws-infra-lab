# ============================================================
# dev 環境參數 — 成本優先
# （Terraform 會自動讀取此檔；alert_email 不放這裡，見 dev.tfvars.example）
# ============================================================

environment = "dev"

# ----- 網路 -----
vpc_cidr            = "10.0.0.0/16"
availability_zones  = ["ap-northeast-1a", "ap-northeast-1c"]
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
app_subnet_cidrs    = ["10.0.11.0/24", "10.0.12.0/24"]
db_subnet_cidrs     = ["10.0.21.0/24", "10.0.22.0/24"]
nat_mode            = "instance" # 1 台 NAT Instance（約 $3/月），接受單點故障

# ----- RDS -----
db_instance_class           = "db.t3.micro"
db_multi_az                 = false # 單一 AZ，省一半資料庫費用
db_deletion_protection      = false # 允許隨時 destroy
db_skip_final_snapshot      = true  # destroy 時不留快照
db_backup_retention_days    = 1
db_apply_immediately        = true
secret_recovery_window_days = 0 # 可立即刪除重建

# ----- ECS -----
ecs_min_tasks = 1
ecs_max_tasks = 2
