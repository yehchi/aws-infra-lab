variable "project_name" {
  description = "專案名稱"
  type        = string
}

variable "environment" {
  description = "環境名稱"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public Subnet IDs（ALB 放這裡）"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "ALB Security Group ID"
  type        = string
}

# ----- Health check 與下線行為 -----

variable "health_check_path" {
  description = "ALB health check 路徑（只檢查程式存活，不依賴資料庫）"
  type        = string
  default     = "/health/live"
}

variable "health_check_interval" {
  description = "Health check 間隔（秒）"
  type        = number
  default     = 10
}

variable "health_check_unhealthy_threshold" {
  description = "連續失敗幾次判定不健康（偵測時間 ≈ interval × 此值）"
  type        = number
  default     = 2
}

variable "deregistration_delay" {
  description = "task 下線前等待進行中請求完成的秒數（AWS 預設 300）"
  type        = number
  default     = 30
}
