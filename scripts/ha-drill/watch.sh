#!/usr/bin/env bash
# ============================================================
# 演練時另開一個分頁執行：每 5 秒顯示 ECS task 數量、ALB target 健康狀態、RDS 狀態
#
# 用法：bash watch.sh prod
# ============================================================
set -u
ENV="${1:-prod}"
CLUSTER="aws-infra-lab-${ENV}-cluster"
SERVICE="aws-infra-lab-${ENV}-app-service"
DB="aws-infra-lab-${ENV}-db"
TG_ARN=$(aws elbv2 describe-target-groups --names "aws-infra-lab-${ENV}-tg" \
  --query "TargetGroups[0].TargetGroupArn" --output text)

while true; do
  NOW=$(date +%H:%M:%S)
  ECS=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query "services[0].[desiredCount,runningCount,pendingCount]" --output text | tr '\t' '/')
  TARGETS=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output text | tr '\t' ':' | tr '\n' ' ')
  RDS=$(aws rds describe-db-instances --db-instance-identifier "$DB" \
    --query "DBInstances[0].[DBInstanceStatus,AvailabilityZone,SecondaryAvailabilityZone]" --output text | tr '\t' ' ')
  echo "$NOW  ECS desired/running/pending=$ECS  |  targets: $TARGETS |  RDS: $RDS"
  sleep 5
done
