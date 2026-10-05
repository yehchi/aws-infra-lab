# ============================================================
# Security Groups Module 變數
# ============================================================

variable "project_name" {
  description = "專案名稱"
  type        = string
}

variable "environment" {
  description = "環境名稱"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID（從 VPC module 輸出取得）"
  type        = string
}
