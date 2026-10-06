# ============================================================
# VPC Module 變數
# ============================================================

variable "project_name" {
  description = "專案名稱"
  type        = string
}

variable "environment" {
  description = "環境名稱"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "availability_zones" {
  description = "使用的 Availability Zones（各層 subnet 數量與此一致）"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public 層 Subnet CIDR（ALB、NAT）"
  type        = list(string)
}

variable "app_subnet_cidrs" {
  description = "App 層 Subnet CIDR（ECS Fargate）"
  type        = list(string)
}

variable "db_subnet_cidrs" {
  description = "Database 層 Subnet CIDR（RDS，無對外路由）"
  type        = list(string)
}

variable "nat_mode" {
  description = "NAT 模式：instance（1 台 NAT Instance，成本優先）或 gateway（每 AZ 一台 NAT Gateway，可用性優先）"
  type        = string
  default     = "instance"

  validation {
    condition     = contains(["instance", "gateway"], var.nat_mode)
    error_message = "nat_mode 只能是 \"instance\" 或 \"gateway\"。"
  }
}
