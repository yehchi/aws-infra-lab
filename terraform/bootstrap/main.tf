# ============================================================
# Bootstrap Stack
# 建一次、不 destroy 的基礎設施：
#   1. S3 bucket：存放 dev/prod 環境的 Terraform state
#   2. GitHub OIDC：讓 GitHub Actions 不用 Access Key 就能操作 AWS
#
# 為什麼要獨立出來？
#   如果放在 dev 環境裡，terraform destroy 時會把 state bucket
#   和 CI 的權限一起刪掉，等於自己把自己鎖在門外。
#
# 本 stack 的 state 存在本機（terraform.tfstate，已被 .gitignore 排除）
# ============================================================

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "aws-infra-lab"
      Stack     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# ============================================================
# 1. Terraform State Bucket
# ============================================================

resource "aws_s3_bucket" "tfstate" {
  # bucket 名稱全球唯一，加上 account id 避免撞名
  bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"

  # 防呆：避免不小心 destroy 掉所有環境的 state
  lifecycle {
    prevent_destroy = true
  }
}

# 版本控制：state 被改壞時可以回到上一版
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 加密：state 裡有 DB 密碼等敏感資訊
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 封鎖所有公開存取
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================
# 2. GitHub Actions OIDC
# ============================================================

# 告訴 AWS：信任 GitHub 簽發的身份憑證
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# GitHub Actions 要扮演的 Role
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions"

  # 信任條件：只有「指定的 GitHub repo」發出的請求才能拿到這個 Role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })

  max_session_duration = 3600 # 臨時憑證最長 1 小時
}

# 權限：Terraform 要建 VPC、IAM Role、RDS... 範圍很廣
# Lab 環境先給 AdministratorAccess，靠上面的「信任條件」限制只有這個 repo 能用
# Production 應改為依實際需要的服務收斂權限（最小權限原則）
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
