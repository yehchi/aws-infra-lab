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

variable "github_repo" {
  description = "允許使用 OIDC Role 的 GitHub repo（格式：owner/repo）"
  type        = string
  default     = "yehchi/aws-infra-lab"
}
