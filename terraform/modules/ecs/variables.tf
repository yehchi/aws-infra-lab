variable "project_name" {
  description = "專案名稱"
  type        = string
}

variable "environment" {
  description = "環境名稱"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet IDs（ECS tasks 跑在這裡）"
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
