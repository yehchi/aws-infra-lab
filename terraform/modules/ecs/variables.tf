variable "project_name" {
  description = "專案名稱"
  type        = string
}

variable "environment" {
  description = "環境名稱"
  type        = string
}

variable "app_subnet_ids" {
  description = "App 層 Subnet IDs（ECS tasks 跑在這裡，跨 2 AZ）"
  type        = list(string)
}

variable "ecs_sg_id" {
  description = "ECS Security Group ID"
  type        = string
}

variable "target_group_arn" {
  description = "ALB Target Group ARN"
  type        = string
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN（DB 連線資訊）"
  type        = string
}

# ----- 容量與 Auto Scaling -----

variable "min_tasks" {
  description = "最少 task 數（prod ≥ 2 才能跨 AZ 高可用）"
  type        = number
  default     = 1
}

variable "max_tasks" {
  description = "Auto Scaling 最多 task 數"
  type        = number
  default     = 2

  validation {
    condition     = var.max_tasks >= 1
    error_message = "max_tasks 至少要 1。"
  }
}

variable "cpu_target_percent" {
  description = "Target Tracking 目標：平均 CPU 使用率維持在此數值附近"
  type        = number
  default     = 50
}

variable "health_check_grace_period" {
  description = "新 task 啟動後的 health check 寬限期（秒）"
  type        = number
  default     = 60
}
