# ============================================================
# 演練監看（Windows PowerShell 版，功能同 watch.sh）
# 每 5 秒顯示 ECS task 數量、ALB target 健康狀態、RDS 狀態
#
# 用法：powershell -ExecutionPolicy Bypass -File watch.ps1 prod
# ============================================================
param([string]$Env = "prod")

$Cluster = "aws-infra-lab-$Env-cluster"
$Service = "aws-infra-lab-$Env-app-service"
$Db      = "aws-infra-lab-$Env-db"
$TgArn   = aws elbv2 describe-target-groups --names "aws-infra-lab-$Env-tg" `
             --query "TargetGroups[0].TargetGroupArn" --output text

while ($true) {
    $now = Get-Date -Format "HH:mm:ss"
    $ecs = (aws ecs describe-services --cluster $Cluster --services $Service `
              --query "services[0].[desiredCount,runningCount,pendingCount]" --output text) -replace "\s+", "/"
    $targets = (aws elbv2 describe-target-health --target-group-arn $TgArn `
              --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output text) -join " " -replace "\t", ":"
    $rds = (aws rds describe-db-instances --db-instance-identifier $Db `
              --query "DBInstances[0].[DBInstanceStatus,AvailabilityZone,SecondaryAvailabilityZone]" --output text) -replace "\t", " "
    Write-Host "$now  ECS desired/running/pending=$ecs  |  targets: $targets  |  RDS: $rds"
    Start-Sleep -Seconds 5
}
