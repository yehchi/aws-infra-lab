# ============================================================
# 高可用演練專用覆寫（只在短時間演練時使用）
#
#   terraform apply   -var-file=drill.tfvars -var-file=prod.tfvars
#   terraform destroy -var-file=drill.tfvars -var-file=prod.tfvars
#
# 演練的架構與正式 prod 完全相同（Multi-AZ、每 AZ 一台 NAT Gateway、2-4 個 task），
# 只放寬「刪除保護」相關設定，讓演練結束後能立即 destroy、停止計費。
# 正式上線時不使用此檔。
# ============================================================

db_deletion_protection      = false
db_skip_final_snapshot      = true
db_apply_immediately        = true
secret_recovery_window_days = 0
