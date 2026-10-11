# 高可用（HA）演練手冊

在 prod 架構上實際製造故障，量測服務中斷時間，驗證架構的高可用設計是否有效。

| 實驗 | 模擬情境 | 驗證的設計 |
|---|---|---|
| 1. 停掉一個 ECS task | 應用程式容器故障 | ECS 至少 2 個 task 分散兩個 AZ、ALB health check 自動移除故障 task |
| 2. RDS 強制故障切換 | 資料庫主機 / 所在 AZ 故障 | RDS Multi-AZ 自動切換到另一個 AZ 的 Standby |
| 3. 壓力測試 | 結算日尖峰流量 | ECS Auto Scaling（Target Tracking，CPU 50%） |

## 0. 準備

1. GitHub → Actions → **Deploy** → Run workflow → environment 選 `prod`、勾選 `drill`
2. AWS Console（region：Tokyo）→ 開啟 **CloudShell**（一般環境即可，ALB 是對外的）
3. 下載腳本並設定變數：

```bash
git clone https://github.com/yehchi/aws-infra-lab.git && cd aws-infra-lab/scripts/ha-drill
export ALB=http://$(aws elbv2 describe-load-balancers --names aws-infra-lab-prod-alb --query "LoadBalancers[0].DNSName" --output text)
export CLUSTER=aws-infra-lab-prod-cluster SERVICE=aws-infra-lab-prod-app-service DB=aws-infra-lab-prod-db
curl -s $ALB/health && echo
python3 seed.py $ALB --count 200
```

4. 另開一個 CloudShell 分頁監看狀態：`cd aws-infra-lab/scripts/ha-drill && bash watch.sh prod`

## 實驗 1：停掉一個 ECS task

```bash
python3 probe.py $ALB --log exp1.csv          # 分頁 A：先開始探測
# 分頁 B：
TASK=$(aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE --query "taskArns[0]" --output text)
aws ecs stop-task --cluster $CLUSTER --task $TASK --reason "HA drill" > /dev/null && date +%T
```

觀察 `watch.sh`：running 從 2 → 1 → ECS 自動補回 2。新 task 健康後，在分頁 A 按 Ctrl+C 看統計。

**要記錄**：live / db 的中斷秒數、ECS 補回新 task 花多久。

## 實驗 2：RDS Multi-AZ 強制故障切換

```bash
python3 probe.py $ALB --log exp2.csv          # 分頁 A
# 分頁 B：
aws rds reboot-db-instance --db-instance-identifier $DB --force-failover > /dev/null && date +%T
```

觀察 `watch.sh`：RDS 狀態 `rebooting` → `available`，主機的 AZ 會對調。恢復後再多觀察 1-2 分鐘才 Ctrl+C。

AWS 端記錄的切換時間：

```bash
aws rds describe-events --source-identifier $DB --source-type db-instance --duration 60 \
  --query "Events[].[Date,Message]" --output text
```

**要記錄**：db 中斷秒數、live 是否全程正常、AWS 事件記錄的切換時間、應用程式是否在資料庫恢復後**立刻**恢復。

## 實驗 3：壓力測試觸發 Auto Scaling

```bash
python3 load.py $ALB --threads 60 --duration 900   # 分頁 A：壓測 15 分鐘
python3 probe.py $ALB --log exp3.csv               # 分頁 C（選做）：量壓測期間的回應時間
```

觀察 `watch.sh`：desired 從 2 → 3 → 4。擴展紀錄：

```bash
aws application-autoscaling describe-scaling-activities --service-namespace ecs \
  --resource-id service/$CLUSTER/$SERVICE --query "ScalingActivities[].[StartTime,StatusCode,Description]" --output text
```

**要記錄**：開始壓測到第一次擴展的時間、擴到幾個 task、停止壓測後多久縮回。

## 結束

GitHub → Actions → **Destroy** → environment 選 `prod`，輸入 `destroy`。
