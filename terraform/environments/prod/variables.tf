# ============================================================
# 變數定義（dev / prod 的 variables.tf 內容完全相同）
#
# 刻意不給「會因環境而不同」的變數預設值：
# 每個環境都必須在 terraform.tfvars 明確寫出自己的選擇，不會不小心沿用別的環境的設定
# ============================================================

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "專案名稱，用於資源命名"
  type        = string
  default     = "aws-infra-lab"
}

variable "environment" {
  description = "環境名稱（dev / prod）"
  type        = string
}

# ----- 網路 -----
variable "vpc_cidr" {
  description = "VPC CIDR（各環境使用不重疊的網段，未來才能互連）"
  type        = string
}

variable "availability_zones" {
  description = "使用的 Availability Zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public 層 Subnet CIDR"
  type        = list(string)
}

variable "app_subnet_cidrs" {
  description = "App 層 Subnet CIDR"
  type        = list(string)
}

variable "db_subnet_cidrs" {
  description = "Database 層 Subnet CIDR"
  type        = list(string)
}

variable "nat_mode" {
  description = "instance（1 台 NAT Instance）或 gateway（每 AZ 一台 NAT Gateway）"
  type        = string
}

# ----- RDS -----
variable "db_instance_class" {
  description = "RDS instance 規格"
  type        = string
}

variable "db_name" {
  description = "資料庫名稱"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "資料庫管理員帳號"
  type        = string
  default     = "dbadmin"
}

variable "db_multi_az" {
  description = "是否啟用 Multi-AZ"
  type        = bool
}

variable "db_deletion_protection" {
  description = "RDS 刪除保護"
  type        = bool
}

variable "db_skip_final_snapshot" {
  description = "刪除時是否略過最終快照"
  type        = bool
}

variable "db_backup_retention_days" {
  description = "自動備份保留天數"
  type        = number
}

variable "db_apply_immediately" {
  description = "RDS 設定變更是否立即套用（false = 等維護時段）"
  type        = bool
}

variable "secret_recovery_window_days" {
  description = "Secret 刪除後的復原等待期（天）"
  type        = number
}

# ----- ECS -----
variable "ecs_min_tasks" {
  description = "最少 task 數"
  type        = number
}

variable "ecs_max_tasks" {
  description = "Auto Scaling 最多 task 數"
  type        = number
}

variable "ecs_cpu_target_percent" {
  description = "Auto Scaling 目標 CPU 使用率（%）"
  type        = number
  default     = 50
}

# ----- 告警 -----
variable "alert_email" {
  description = "告警通知 email（不進版控：本機用 dev.tfvars / prod.tfvars，CI 用 GitHub Secret）"
  type        = string
  sensitive   = true
}
