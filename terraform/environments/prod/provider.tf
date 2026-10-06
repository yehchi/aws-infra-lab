# ============================================================
# Provider 設定（dev / prod 的 provider.tf 內容完全相同）
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
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
