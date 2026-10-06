variable "project_name" {
  description = "專案名稱"
  type        = string
}

variable "environment" {
  description = "環境名稱"
  type        = string
}

variable "db_subnet_ids" {
  description = "Database 層 Subnet IDs（RDS 只放在這一層）"
  type        = list(string)
}

variable "rds_sg_id" {
  description = "RDS Security Group ID"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance 規格"
  type        = string
  default     = "db.t3.micro"
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

# ----- dev / prod 差異參數 -----

variable "multi_az" {
  description = "是否啟用 Multi-AZ（另一個 AZ 維持同步複寫的 Standby，故障自動切換）"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "刪除保護：true 時 terraform destroy 會被拒絕，必須先手動關閉"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "刪除時是否略過最終快照（prod 應為 false，保留最後一份資料）"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "自動備份保留天數"
  type        = number
  default     = 7
}

variable "apply_immediately" {
  description = "設定變更是否立即套用（false = 等到維護時段才套用，避免營業時間重啟）"
  type        = bool
  default     = true
}

variable "secret_recovery_window_days" {
  description = "Secret 刪除後的復原等待期（0 = 立即刪除；正式環境建議 7-30 天）"
  type        = number
  default     = 0
}
