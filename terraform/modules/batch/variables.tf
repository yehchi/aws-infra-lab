variable "project_name" {
  description = "專案名稱"
  type        = string
}

variable "environment" {
  description = "環境名稱"
  type        = string
}

variable "cluster_arn" {
  description = "ECS Cluster ARN（批次任務跟線上服務跑在同一個 cluster）"
  type        = string
}

variable "app_subnet_ids" {
  description = "App 層 Subnet IDs（批次任務跟線上服務同一層網路，可連資料庫）"
  type        = list(string)
}

variable "ecs_sg_id" {
  description = "ECS Security Group ID（沿用：RDS 只放行這個 SG）"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR Repository URL（跟線上服務同一份 image）"
  type        = string
}

variable "task_execution_role_arn" {
  description = "ECS Task Execution Role ARN（拉 image、寫 log、讀 secret）"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group 名稱（與線上服務共用，stream 前綴為 batch）"
  type        = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN（DB 連線資訊，含讀取 endpoint）"
  type        = string
}

variable "sns_topic_arn" {
  description = "告警用 SNS Topic ARN（批次失敗通知沿用既有告警管道）"
  type        = string
}

variable "schedule_expression" {
  description = "批次排程（台灣時間）。預設週一到週五 14:30，台股 13:30 收盤後一小時"
  type        = string
  default     = "cron(30 14 ? * MON-FRI *)"
}

variable "schedule_enabled" {
  description = "是否啟用自動排程（false = 只能手動執行）"
  type        = bool
  default     = true
}
