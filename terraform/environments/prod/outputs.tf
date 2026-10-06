# ============================================================
# 輸出值（dev / prod 的 outputs.tf 內容完全相同）
# ============================================================

output "environment" {
  description = "環境名稱"
  value       = var.environment
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "nat_mode" {
  description = "NAT 模式"
  value       = module.vpc.nat_mode
}

output "alb_dns_name" {
  description = "ALB DNS name（用這個網址存取服務）"
  value       = module.alb.alb_dns_name
}

output "db_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_endpoint
}

output "db_multi_az" {
  description = "RDS 是否為 Multi-AZ"
  value       = module.rds.multi_az
}

output "ecr_repository_url" {
  description = "ECR Repository URL"
  value       = module.ecs.ecr_repository_url
}

output "ecs_cluster_name" {
  description = "ECS Cluster 名稱"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS Service 名稱"
  value       = module.ecs.service_name
}
