output "state_machine_arn" {
  description = "收盤後批次的 Step Functions ARN（手動執行 / redrive 用）"
  value       = aws_sfn_state_machine.batch.arn
}

output "state_machine_name" {
  description = "收盤後批次的 Step Functions 名稱"
  value       = aws_sfn_state_machine.batch.name
}

output "schedule_name" {
  description = "EventBridge Scheduler 排程名稱"
  value       = aws_scheduler_schedule.eod.name
}

output "drill_param_prefix" {
  description = "演練開關的 SSM 參數路徑前綴"
  value       = local.param_prefix
}
