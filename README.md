# aws-infra-lab

以虛構的中型證券商「IBM 證券」為情境，用 Terraform 在 AWS 上建置一套可上線等級的容器化架構，
並以 GitHub Actions 管理完整的 IaC 生命週期（plan → apply → 部署 → 演練 → destroy）。

應用程式是一支刻意保持極簡的「交易紀錄查詢 API」（FastAPI），重點在架構設計與每個決策背後的理由。
設計理念、客戶痛點與技術選型的完整說明見 [AWS_SideProject_Spec.md](AWS_SideProject_Spec.md)。

## 架構

完整架構圖（AWS 官方圖示，可用 [draw.io](https://app.diagrams.net) 開啟）：[docs/architecture.drawio](docs/architecture.drawio)

```
 使用者 ──► Internet Gateway ──► ALB（Public 層，跨 2 AZ）
                                   │ :8000（ECS SG 只收 ALB SG）
                                   ▼
                           ECS Fargate（App 層，Auto Scaling）──► NAT ──► 對外（拉 image、呼叫 AWS API）
                                   │ :5432（RDS SG 只收 ECS SG）
                                   ▼
                           RDS PostgreSQL（Database 層，無任何對外路由）

 區域服務：ECR（image tag = commit hash）· Secrets Manager（DB 帳密）· CloudWatch → SNS 告警
```

| 設計 | 理由 |
|---|---|
| 三層式子網路（Public / App / Database × 2 AZ） | 資料庫網段沒有對外路由，即使應用層被入侵，資料也無法直接送出 VPC |
| ECS Fargate + Auto Scaling（CPU 50%） | 免管主機；尖峰自動擴展、離峰縮減，成本跟負載對齊 |
| ALB 只檢查 `/health/live`（不查資料庫） | 資料庫故障切換時，不會連帶讓所有 task 被判定不健康而全部重啟 |
| Secrets Manager + IAM Role | 密碼由 Terraform 自動產生，不進程式碼、不進版控 |
| GitHub Actions + OIDC | CI/CD 不存任何長期 Access Key，只信任此 repo 的不可變 ID |

## 環境

dev 與 prod 呼叫同一份 Terraform module，`main.tf` / `variables.tf` 完全相同，差異只在 `terraform.tfvars`：

| 參數 | dev（成本優先） | prod（可用性優先） |
|---|---|---|
| NAT | 1 台 NAT Instance | 每 AZ 一台 NAT Gateway |
| RDS | Single-AZ | Multi-AZ + 刪除保護 |
| ECS task（最少 / 最多） | 1 / 2 | 2 / 4 |
| 備份保留 | 1 天 | 14 天 |

```
terraform/
├── bootstrap/          # 建一次、不 destroy：Terraform state（S3）、GitHub OIDC Role
├── modules/            # vpc / security_groups / alb / ecs / rds / cloudwatch
└── environments/
    ├── dev/            # terraform.tfvars = dev 參數
    └── prod/           # terraform.tfvars = prod 參數；drill.tfvars = 演練用覆寫
```

## CI/CD

| Workflow | 觸發 | 做什麼 |
|---|---|---|
| `pr-check.yml` | 開 PR | ruff lint、docker build、dev 與 prod 同時 `terraform plan` |
| `deploy.yml` | merge 到 main（dev）/ 手動（dev 或 prod） | terraform apply → build & push ECR → ECS 部署 → 健康檢查 → Job Summary 顯示網址 |
| `destroy.yml` | 手動（選環境 + 輸入 `destroy`） | terraform destroy，停止計費 |

## 高可用演練

腳本與操作手冊：[scripts/ha-drill/](scripts/ha-drill/)

| 實驗 | 實測結果 |
|---|---|
| 停掉一個 ECS task | 1,050 次請求 0 失敗；53 秒自動補回 |
| RDS Multi-AZ 強制故障切換 | 資料庫中斷 12.7 秒；`/health/live` 全程 100%，ECS 未重啟任何 task |
| 壓力測試 | 伺服器端 CPU 約 10%、瓶頸在用戶端，Auto Scaling 正確判斷不擴展 |

## 專案結構

```
├── app/                 # FastAPI 交易紀錄查詢服務 + Dockerfile
├── terraform/           # 見上方「環境」
├── .github/workflows/   # pr-check / deploy / destroy
├── scripts/ha-drill/    # 高可用演練腳本（probe / load / seed / watch）
├── docs/                # 架構圖
└── AWS_SideProject_Spec.md
```
