# 這兩個值要設定到 GitHub repo 的 Variables（Settings → Secrets and variables → Actions）

output "tfstate_bucket" {
  description = "Terraform state bucket 名稱 → GitHub Variable: TF_STATE_BUCKET"
  value       = aws_s3_bucket.tfstate.bucket
}

output "github_actions_role_arn" {
  description = "GitHub Actions 要扮演的 Role ARN → GitHub Variable: AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
