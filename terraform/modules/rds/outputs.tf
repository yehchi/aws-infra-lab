output "db_endpoint" {
  description = "RDS endpoint（host:port）"
  value       = aws_db_instance.main.endpoint
}

output "db_address" {
  description = "RDS hostname"
  value       = aws_db_instance.main.address
}

output "secret_arn" {
  description = "Secrets Manager ARN（ECS Task 用這個讀取 DB 連線資訊）"
  value       = aws_secretsmanager_secret.db_credentials.arn
}
