# ============================================================
# Remote State Backend
# State 存在 S3，讓本機和 GitHub Actions 讀寫同一份 state
#
# bucket 名稱含 AWS account id，不寫死在 public repo，init 時再帶入：
#   terraform init -backend-config="bucket=<TF_STATE_BUCKET>"
# ============================================================

terraform {
  backend "s3" {
    key          = "dev/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true # S3 原生鎖：同一時間只允許一個人 apply，避免 state 被同時改壞
  }
}
