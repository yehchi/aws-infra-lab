output "cluster_name" {
  description = "ECS Cluster 名稱"
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "ECS Service 名稱"
  value       = aws_ecs_service.app.name
}

output "ecr_repository_url" {
  description = "ECR Repository URL（push image 用）"
  value       = aws_ecr_repository.app.repository_url
}

output "task_execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  value       = aws_iam_role.ecs_task_execution.arn
}
