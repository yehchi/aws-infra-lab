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

output "cluster_arn" {
  description = "ECS Cluster ARN（批次排程任務用）"
  value       = aws_ecs_cluster.main.arn
}

output "log_group_name" {
  description = "容器 log group 名稱（批次任務共用）"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "task_family" {
  description = "線上服務的 task definition family（部署時用最新版）"
  value       = aws_ecs_task_definition.app.family
}

output "task_execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  value       = aws_iam_role.ecs_task_execution.arn
}
