# 收盤後批次演練手冊

驗證批次作業的三件事：流程能自動跑完、失敗能從中斷處續跑、執行時不影響線上交易。

| 實驗 | 模擬情境 | 驗證的設計 |
|---|---|---|
| 1. 正常執行＋重跑 | 收盤後自動跑完結算 → 交割 → 報表；同一天重跑一次 | Step Functions 串接三個 ECS 排程任務；每一步冪等，重跑結果相同 |
| 2. 中途失敗＋續跑 | 交割步驟失敗（例如上游資料異常） | 自動重試 → 仍失敗則停在該步驟並發 SNS 告警 → 修正後 Redrive，只重跑失敗的步驟，已完成的結算不重跑；失敗的交易整筆回滾，不留半套資料 |
| 3. 批次期間的線上服務 | 大型報表在收盤後執行 | 報表讀 Read Replica，主庫與線上寫入（下單）不受影響 |

> 實驗 1、2 在 dev 就能做；實驗 3 需要 Read Replica，要在 prod 演練環境做。
> 以下指令為 **Windows PowerShell**，在 `scripts/` 底下執行。

## 0. 準備

1. 環境：dev 由 merge 自動部署；prod 用 GitHub Actions → **Deploy** → `prod` + 勾選 `drill`（需 Approve）
2. 設定變數（`$ENV` 換成 `dev` 或 `prod`）：

```powershell
$ENV = "dev"
$ALB = "http://" + (aws elbv2 describe-load-balancers --names "aws-infra-lab-$ENV-alb" --query "LoadBalancers[0].DNSName" --output text)
$SM  = aws stepfunctions list-state-machines --query "stateMachines[?name=='aws-infra-lab-$ENV-eod-batch'].stateMachineArn" --output text
$P   = "/aws-infra-lab/$ENV/batch"
curl.exe -s "$ALB/health"          # read_from：dev = primary、prod = replica
python ha-drill\seed.py $ALB --count 500
```

3. 常用查詢（每個實驗都會用到）：

```powershell
# 執行狀態
aws stepfunctions describe-execution --execution-arn $EXEC --query "[status,startDate,stopDate]" --output text
# 每一步的進出時間（看哪一步跑了、跑多久）
aws stepfunctions get-execution-history --execution-arn $EXEC --max-results 200 `
  --query "events[?type=='TaskStateEntered' || type=='TaskStateExited' || type=='TaskFailed'].[timestamp,type,stateEnteredEventDetails.name || stateExitedEventDetails.name || '']" --output table
# 批次 log（每步的筆數、耗時、讀主庫還是複本）
aws logs tail "/ecs/aws-infra-lab-$ENV" --log-stream-name-prefix batch --since 20m
```

## 實驗 1：正常執行＋重跑

```powershell
$EXEC = aws stepfunctions start-execution --state-machine-arn $SM --query executionArn --output text; Get-Date -Format HH:mm:ss
# 約 3～5 分鐘後查狀態 → SUCCEEDED，看 history 與 log
# 同一天再跑一次，比對 log 裡的筆數是否完全相同（冪等）
$EXEC = aws stepfunctions start-execution --state-machine-arn $SM --query executionArn --output text
```

**要記錄**：整體耗時、每一步耗時、結算 / 交割 / 報表的筆數、兩次執行的筆數是否一致、報表的 `read_from`。

## 實驗 2：中途失敗＋從中斷處續跑

```powershell
# ① 讓交割步驟失敗
aws ssm put-parameter --name "$P/fail-step" --value clearing --overwrite
$EXEC = aws stepfunctions start-execution --state-machine-arn $SM --query executionArn --output text; Get-Date -Format HH:mm:ss
# ② 等狀態變 FAILED（含 1 次自動重試，約 3～4 分鐘）→ 檢查信箱是否收到【批次告警】
# ③ 「修正問題」：把開關改回正常
aws ssm put-parameter --name "$P/fail-step" --value none --overwrite
# ④ 從中斷處續跑
aws stepfunctions redrive-execution --execution-arn $EXEC; Get-Date -Format HH:mm:ss
# ⑤ 再看 history：Settlement 不會再出現第二次 Entered，直接從 Clearing 開始
```

**要記錄**：失敗發生時間、重試次數、告警信收到的時間、redrive 後是否只跑 Clearing → Report、最終狀態。

## 實驗 3：批次期間的線上服務（prod）

```powershell
$ENV = "prod"   # 重新執行「0. 準備」的變數設定
# ① 基準：沒有批次時，探測 3 分鐘後 Ctrl+C
python ha-drill\probe.py $ALB --write --log batch-base.csv
# ② 讓報表步驟對複本施壓 5 分鐘（模擬大型法規報表）
aws ssm put-parameter --name "$P/report-load-seconds" --value 300 --overwrite
# ③ 視窗 A：開始探測；視窗 B：啟動批次。等報表步驟結束後，視窗 A 按 Ctrl+C
python ha-drill\probe.py $ALB --write --log batch-during.csv
$EXEC = aws stepfunctions start-execution --state-machine-arn $SM --query executionArn --output text; Get-Date -Format HH:mm:ss
# ④ 收尾：把施壓改回 0
aws ssm put-parameter --name "$P/report-load-seconds" --value 0 --overwrite
```

CloudWatch → Metrics → Source，貼上下列設定（時間改成實驗時段，時區選 Local），截圖主庫與複本的 CPU、複本延遲：

```json
{
  "view": "timeSeries", "stacked": false, "region": "ap-northeast-1", "period": 60,
  "title": "批次期間：主庫 vs 複本",
  "metrics": [
    [ "AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "aws-infra-lab-prod-db", { "label": "主庫 CPU" } ],
    [ "...", "aws-infra-lab-prod-db-replica", { "label": "複本 CPU" } ],
    [ "AWS/RDS", "ReplicaLag", "DBInstanceIdentifier", "aws-infra-lab-prod-db-replica", { "label": "複本延遲（秒）", "yAxis": "right" } ]
  ]
}
```

**要記錄**：基準 vs 批次期間的 write（下單）與 db（查詢）延遲平均 / p95、失敗數；主庫 CPU 與複本 CPU；複本延遲。

> 預期：寫入走主庫，不受報表影響；查詢目前也讀同一台複本，可能被大型報表拖慢 → 這是要觀察的取捨。

## 結束

- 確認兩個 SSM 開關都已改回 `none` / `0`
- prod：GitHub Actions → **Destroy** → `prod`，輸入 `destroy`
