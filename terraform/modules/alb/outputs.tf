output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "ALB DNS name（用這個網址存取你的服務）"
  value       = aws_lb.main.dns_name
}

output "target_group_arn" {
  description = "Target Group ARN（ECS Service 要用）"
  value       = aws_lb_target_group.ecs.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix（CloudWatch metric 用）"
  value       = aws_lb.main.arn_suffix
}
