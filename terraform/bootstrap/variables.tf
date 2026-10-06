variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "專案名稱"
  type        = string
  default     = "aws-infra-lab"
}

variable "github_oidc_sub_prefix" {
  description = <<-EOT
    GitHub OIDC token 的 sub claim 前綴（不可變 ID 格式）。
    查詢方式：GET https://api.github.com/repos/<owner>/<repo>/actions/oidc/customization/sub
    回傳的 sub_claim_prefix 欄位即為此值。
  EOT
  type        = string
  default     = "repo:yehchi@105764099/aws-infra-lab@1405500914"
}
