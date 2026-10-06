variable "project_name" {
  description = "專案名稱"
  type        = string
}

variable "environment" {
  description = "環境名稱"
  type        = string
}

variable "alert_email" {
  description = "告警通知的 email"
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS Cluster 名稱"
  type        = string
}

variable "ecs_service_name" {
  description = "ECS Service 名稱"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix（CloudWatch metric 用）"
  type        = string
}

variable "rds_instance_id" {
  description = "RDS Instance identifier"
  type        = string
}

variable "rds_connections_threshold" {
  description = "RDS 連線數告警閾值（db.t3.micro 的 max_connections 約 80-110）"
  type        = number
  default     = 60
}
