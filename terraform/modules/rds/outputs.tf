output "db_endpoint" {
  description = "RDS endpoint（host:port）"
  value       = aws_db_instance.main.endpoint
}

output "db_address" {
  description = "RDS hostname"
  value       = aws_db_instance.main.address
}

output "db_instance_id" {
  description = "RDS instance identifier（CloudWatch 告警用）"
  value       = aws_db_instance.main.identifier
}

output "multi_az" {
  description = "是否為 Multi-AZ"
  value       = aws_db_instance.main.multi_az
}

output "replica_instance_id" {
  description = "Read Replica identifier（沒有複本時為 null）"
  value       = var.create_read_replica ? aws_db_instance.replica[0].identifier : null
}

output "read_endpoint" {
  description = "讀取用 endpoint（有複本指向複本，否則指向主庫）"
  value       = var.create_read_replica ? aws_db_instance.replica[0].address : aws_db_instance.main.address
}

output "secret_arn" {
  description = "Secrets Manager ARN（ECS Task 用這個讀取 DB 連線資訊）"
  value       = aws_secretsmanager_secret.db_credentials.arn
}
