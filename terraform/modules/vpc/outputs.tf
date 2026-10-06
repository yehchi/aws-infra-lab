# ============================================================
# VPC Module 輸出
# ============================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public 層 Subnet IDs（ALB 用）"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "App 層 Subnet IDs（ECS 用）"
  value       = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  description = "Database 層 Subnet IDs（RDS 用）"
  value       = aws_subnet.database[*].id
}

output "nat_mode" {
  description = "目前使用的 NAT 模式"
  value       = var.nat_mode
}
