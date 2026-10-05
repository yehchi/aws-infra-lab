output "sns_topic_arn" {
  description = "SNS Topic ARN（告警通知管道）"
  value       = aws_sns_topic.alerts.arn
}
