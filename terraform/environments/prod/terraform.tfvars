# ============================================================
# prod 環境參數 — 可用性優先
# （Terraform 會自動讀取此檔；alert_email 不放這裡，見 prod.tfvars.example）
#
# 跟 dev 呼叫的是同一份 module，差異只有這個檔案：
#   diff ../dev/terraform.tfvars terraform.tfvars
# ============================================================

environment = "prod"

# ----- 網路 -----
vpc_cidr            = "10.1.0.0/16" # 與 dev（10.0.0.0/16）不重疊，未來可做 VPC 互連
availability_zones  = ["ap-northeast-1a", "ap-northeast-1c"]
public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
app_subnet_cidrs    = ["10.1.11.0/24", "10.1.12.0/24"]
db_subnet_cidrs     = ["10.1.21.0/24", "10.1.22.0/24"]
nat_mode            = "gateway" # 每 AZ 一台 NAT Gateway，單一 AZ 故障不影響另一個 AZ 對外

# ----- RDS -----
db_instance_class           = "db.t3.micro"
db_multi_az                 = true  # 另一個 AZ 維持同步 Standby，故障自動切換
db_deletion_protection      = true  # 防止誤刪：destroy 會被拒絕
db_skip_final_snapshot      = false # 刪除前保留最後一份快照
db_backup_retention_days    = 14
db_apply_immediately        = false # 設定變更等到維護時段才套用，避免營業時間重啟
secret_recovery_window_days = 7

# ----- ECS -----
ecs_min_tasks = 2 # 至少 2 個 task，分散在兩個 AZ
ecs_max_tasks = 4 # 尖峰（如結算日）最多擴展到 4 個
