# ============================================================
# 輸出值
# terraform apply 完成後會顯示這些資訊
# ============================================================

# ----- VPC -----
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public Subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private Subnet IDs"
  value       = module.vpc.private_subnet_ids
}

# ----- Security Groups -----
output "alb_security_group_id" {
  description = "ALB Security Group ID"
  value       = module.security_groups.alb_sg_id
}

output "ecs_security_group_id" {
  description = "ECS Security Group ID"
  value       = module.security_groups.ecs_sg_id
}

output "rds_security_group_id" {
  description = "RDS Security Group ID"
  value       = module.security_groups.rds_sg_id
}

# ----- ALB -----
output "alb_dns_name" {
  description = "ALB DNS name（用這個網址存取你的服務）"
  value       = module.alb.alb_dns_name
}

# ----- RDS -----
output "db_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_endpoint
}

# ----- ECS -----
output "ecr_repository_url" {
  description = "ECR Repository URL（push image 用）"
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
