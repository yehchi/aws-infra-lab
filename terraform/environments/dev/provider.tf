# ============================================================
# Provider 設定
# 告訴 Terraform：我要用 AWS，region 是東京（ap-northeast-1）
# ============================================================

terraform {
  required_version = ">= 1.10.0" # S3 原生 lockfile 需要 1.10+

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "aws-infra-lab"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
