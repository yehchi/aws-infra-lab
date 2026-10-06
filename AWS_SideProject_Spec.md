# AWS Side Project 規格書

> **文件目的**：本文件定義專案的設計理念、商業邏輯與技術選型依據，作為技術簡報與架構說明的核心參考資料。
> **專案定位**：以一個虛構但貼近真實的金融業客戶場景，展示「為什麼要用雲端 + IaC 的方式管理基礎架構」，聚焦設計理念與商業效益，而非技術炫耀。
> **撰寫日期**：2026 年 10 月（更新版）

---

## 一、專案背景與目標

### 1.1 為什麼做這個專案

這個專案要回答的不是「我會哪些技術」，而是一個更根本的問題：**企業為什麼要用雲端和 IaC 來管理基礎架構？這樣做的目的是什麼？能解決什麼問題？帶來什麼實際效益？**

為了讓這些問題不流於空泛，我們以一個虛構但貼近真實的金融業客戶場景作為出發點，讓每一個架構決策都有對應的商業理由。

### 1.2 分析框架：AWS Well-Architected Framework 六大支柱

本專案的所有設計決策，都以 AWS Well-Architected Framework 的六大支柱作為分析框架：

1. **卓越營運（Operational Excellence）** — 能不能用自動化、標準化的方式運維，減少人為錯誤？
2. **安全性（Security）** — 資料和系統的存取控制是否到位？能不能通過稽核？
3. **可靠性（Reliability）** — 單點故障時服務能不能繼續運作？能不能從災難中恢復？
4. **效能效率（Performance Efficiency）** — 資源配置是否能隨需求彈性調整？
5. **成本最佳化（Cost Optimization）** — 花的錢是否跟實際使用量對齊？有沒有浪費？
6. **永續性（Sustainability）** — 資源利用效率是否合理？能不能減少不必要的能耗？

---

## 二、客戶場景（Persona）

### 2.1 客戶背景：中型證券商「IBM 證券」（虛構）

**公司概況**：國內中型證券商，約 800 名員工，有線上下單系統和內部後台管理系統。IT 部門 15 人，其中 3 人負責基礎架構維運。

**現有環境（地端機房）**：兩台實體伺服器跑後台管理系統（Java 應用），一台跑 Oracle 資料庫，放在公司自有機房。備份靠另一台 NAS，沒有異地備援。網路架構扁平，應用程式和資料庫在同一個 VLAN。

### 2.2 客戶痛點（以六大支柱對應）

#### 痛點 1：營運效率低落（Operational Excellence）

IT 要開一個新的測試環境，得寫簽呈申請硬體、等採購、等到貨、裝機、裝 OS、部署應用 — 流程走完最快三週。趕的時候工程師自己手動裝，但每次裝出來的環境都有細微差異，「在測試機上能跑，上 production 就爆」是常態。系統設定全靠資深工程師的經驗和筆記，沒有統一的文件或自動化流程。

#### 痛點 2：安全性不足（Security）

資料庫跟應用程式在同一個網段，網路沒有做分層隔離。DB 密碼寫在 application config 檔裡，上一次換密碼是兩年前。誰存取了哪些資料沒有完整的 audit log。金管會近幾年對資安稽核越來越嚴，每次稽核前都是全部門加班補文件。

#### 痛點 3：可靠性堪憂（Reliability）

只有一個機房，沒有異地備援。去年機房空調故障，伺服器過熱停機 4 小時，內部後台系統全部中斷。備份是每晚跑一次到 NAS，但從來沒有真正做過災難恢復演練 — 沒有人確定備份真的能還原成功。RTO（恢復時間目標）和 RPO（恢復點目標）都是口頭上的數字，沒有實際驗證過。

#### 痛點 4：效能無法彈性調整（Performance Efficiency）

每月結算日系統負載是平日的 3-5 倍，但伺服器規格是固定的。為了撐過尖峰買的高規格硬體，平常 80% 的運算力都閒置。想要擴展就得再買一台，但預算有限，而且新機器到位前這一波尖峰已經過了。

#### 痛點 5：成本結構僵化（Cost Optimization）

三年前買的伺服器今年到保固期了，要嘛花一大筆續保，要嘛花更大一筆買新的。不管業務量有沒有成長，這筆錢都得花。而且維運人力成本也高 — 3 個基礎架構工程師有大量時間花在 patch OS、換硬碟、處理硬體故障，真正做架構改善的時間不到 20%。

#### 痛點 6：永續性與擴展性不足（Sustainability）

機房的電費逐年上升，而且老舊設備的能耗效率遠不如雲端資料中心。公司有 ESG 報告的壓力，但沒有具體的碳排數據可以追蹤。

---

## 三、為什麼要上雲？

不是「雲比較好」，而是要回答客戶一個問題：**你現在的痛點是什麼，雲能不能解決，值不值得。**

### 3.1 成本面（CapEx → OpEx）

地端機房是 CapEx（資本支出），買了就是你的，不管用不用都要攤提折舊、付電費、養維運人力。雲是 OpEx（營運支出），用多少付多少。但雲不一定比較便宜 — 如果你的 workload 是 24/7 穩定高負載，地端可能更划算。雲真正省錢的場景是**需求波動大**的情境：尖峰時段擴展、離峰縮減、開發測試環境用完即銷毀。所以不是「雲比較便宜」，而是「雲讓你的成本結構跟實際使用量對齊」。

### 3.2 可靠性（自建容災 vs. 雲端 AZ）

地端要做到跨機房容災，你得自己建第二個機房、拉專線、做資料同步。雲上你只要選兩個 Availability Zone，AWS 幫你把底層的電力、網路、硬體冗餘都處理好了。你買到的不是機器，是 SLA。

### 3.3 安全性（責任共擔模型）

雲不是「把東西放在別人那裡不安全」，而是責任共擔模型：AWS 負責「雲的安全」（實體機房、硬體、hypervisor），你負責「雲裡的安全」（IAM、網路隔離、加密）。對多數企業來說，AWS 機房的實體安全等級遠高於自建機房。

### 3.4 營運效率（週級 → 分鐘級）

地端擴容從提需求、採購、到上線可能幾週到幾個月。雲上幾分鐘。這不只是快，而是讓你的 IT 能跟上業務的速度。

---

## 四、為什麼用 Terraform？（技術選型與取捨）

### 4.1 IaC 工具比較

IaC 工具有三個主要選項，每個都有代價：

**CloudFormation** — AWS 原生、免費、跟 AWS 服務整合最深。但它只能管 AWS，而且 JSON/YAML 模板一長起來很難讀、難維護。如果客戶確定只用 AWS 且團隊規模小，這其實是成本最低的選擇。

**AWS CDK** — 可以用 Python/TypeScript 寫，對開發者友善。但底層還是編譯成 CloudFormation，debug 時你得看兩層東西，學習曲線反而更陡。

**Terraform** — 跨雲、社群生態大、人才市場好找人。但它有額外的學習成本（HCL 語法）、state 管理是個必須處理的議題（state 檔案遺失或衝突會很痛），而且如果要用進階功能（Terraform Cloud/Enterprise），是要付費的。

### 4.2 選擇 Terraform 的商業理由

對一個平台團隊來說，你不太可能只服務一朵雲。今天客戶用 AWS，明天可能多一個 Azure 的案子。Terraform 讓團隊用同一套工具、同一套流程管理不同的雲，降低的是「人的切換成本」。而且市場上 Terraform 人才最多，未來擴編比較容易。這個彈性值得 state 管理的額外複雜度。

### 4.3 Terraform 在本專案中的定位與核心效益

本專案將 Terraform 定位為「自動化平台部署」的標準工具，並與 CI/CD 管線整合使用。預期帶來的核心效益如下：

- **配合頻繁的測試需求，快速部署資源** — 透過 `terraform apply` 快速建置環境
- **因應臨時測試需求，快速部署和快速銷毀環境** — 透過 apply/destroy 生命週期管理
- **重複/一致性基礎設施、配置模組化** — 透過 modules 目錄結構設計
- **於部署前預覽變更，降低錯誤配置** — 透過 `terraform plan` 的變更預覽功能
- **節省成本（降低雲端資源費用）** — 搭配本專案的成本最佳化策略
- **支援多種雲端供應商** — 選擇 Terraform 而非 CloudFormation 的跨雲彈性理由

### 4.4 為什麼用 IaC 生命週期管理？

**成本最佳化** — 開發測試環境不需要 24/7 運行。`terraform apply` 建環境驗證，`terraform destroy` 用完銷毀。一個月只開幾天，成本可以壓到持續運行的 10-20%。

**可靠性** — 能隨時 destroy 再 apply 回來，代表你的 code 是 single source of truth。這就是 disaster recovery 能力的證明：不是「我們有備份」，而是「我們能從零重建，而且自動化」。

**卓越營運** — 每次 apply 都是走同一份 code，不會出現「某個人手動改了一個設定但沒人知道」的 drift 問題。基礎架構的變更跟應用程式的變更走一樣的流程：寫 code → PR review → 合併 → 自動部署。

**安全性** — 基礎架構變更必須經過 code review 才能合併，等於多了一層人工審查。不會有人偷偷在 Console 開了一個 0.0.0.0/0 的 Security Group 沒人發現。

---

## 五、目標架構

### 5.1 架構圖（文字版）

```
                    [ GitHub Repository ]
                            |
                    GitHub Actions (CI/CD)
                            |
                    terraform apply
                            |
    ┌──────────────────── VPC（跨 2 AZ）────────────────────┐
    │                                                       │
    │  Public 層    [ ALB ]            [ NAT ]              │
    │                  │                  ▲                 │
    │                  ▼ :8000            │ 對外連線         │
    │  App 層       [ ECS Fargate ] ──────┘                 │
    │               （Auto Scaling）                         │
    │                  │ :5432                              │
    │                  ▼                                    │
    │  Database 層  [ RDS PostgreSQL ]  ← 無任何對外路由     │
    │                                                       │
    └───────────────────────────────────────────────────────┘
                            │
              [ Secrets Manager ]  [ CloudWatch ]
                  (DB 連線資訊)      (Logs + Alarm)

完整架構圖（AWS 官方圖示）：docs/architecture.drawio
```

### 5.2 架構設計決策與商業理由（對應客戶痛點）

| 客戶痛點 | 設計決策 | 對應支柱 | 怎麼解決 |
|---|---|---|---|
| 環境不一致、手動部署耗時三週 | Terraform IaC | 卓越營運 | 一份 code 建出完全相同的 dev/staging/prod，消除環境差異，部署從週級縮短到分鐘級 |
| 測試環境長期佔用硬體成本 | Terraform apply/destroy 生命週期 | 成本最佳化 | 測試環境用完即銷毀，不再需要長期養一台測試機 |
| DB 密碼寫死在 config、無 audit log | Secrets Manager + IAM Role | 安全性 | 密碼由 Terraform 自動產生、集中管理，所有存取都有 log，稽核時直接拉報表 |
| 資料庫與應用同網段、無隔離 | VPC 三層式子網路（Public / App / Database） | 安全性 | 資料庫獨立一層、route table 沒有任何對外路由，外部碰不到、資料也送不出去，符合金管會網路隔離要求 |
| 單機房無備援、空調故障停機 4 小時 | prod：Multi-AZ 部署（ALB + 2 個以上 ECS task + RDS Multi-AZ + 每 AZ 一台 NAT Gateway） | 可靠性 | 跨兩個 AZ，單一機房級故障服務不中斷；dev 為省成本採單 AZ 元件 |
| 備份沒做過 DR 演練 | Terraform destroy + apply | 可靠性 | 整個環境從零重建只要幾分鐘，DR 不再是紙上談兵 |
| 結算日負載 3-5 倍但硬體規格固定 | ECS Service Auto Scaling（Target Tracking，CPU 50%） | 效能效率 | 按任務數計費，尖峰自動擴展（prod 2 → 4 task）、離峰自動縮減，成本跟負載對齊 |
| 伺服器保固到期需大筆資本支出 | 雲端 OpEx 模型 | 成本最佳化 | 從一次性大額資本支出變成按月營運費用，現金流更好預測 |
| 3 位工程師 80% 時間花在硬體維運 | Fargate + Managed Services | 卓越營運 | 不需管 OS patch、硬碟更換，工程師時間釋放到架構改善 |
| 基礎架構變更無審查流程 | GitHub PR + Actions CI/CD | 安全性 + 卓越營運 | 變更走 code review 流程，誰改了什麼、為什麼改，全部有紀錄 |
| 缺乏主動監控與告警 | CloudWatch Logs + Metrics + Alarm | 卓越營運 | 日誌集中收集、設定告警閾值，問題發生前收到通知而不是等使用者報修 |
| NAT Gateway 成本偏高 | NAT Instance 取代 NAT Gateway | 成本最佳化 | 功能相同但月費從 $30-40 降到 ~$5，對非 production 環境是合理取捨 |

### 5.3 元件清單與設計理由

| 元件 | 用途 | 設計理由 |
|---|---|---|
| **VPC** | 網路隔離的基礎 | 建立獨立網段，不使用 default VPC，展示對網路規劃的掌握 |
| **Public Subnet（跨 2 個 AZ）** | 放置 ALB | 跨 AZ 是為了高可用性；ALB 需要對外接受流量故置於公有網段 |
| **App Subnet（跨 2 個 AZ）** | 放置 ECS Fargate | 應用程式不直接暴露於網際網路，僅能透過 ALB 存取；可經 NAT 主動對外（拉 image、呼叫 AWS API） |
| **Database Subnet（跨 2 個 AZ）** | 放置 RDS | route table 不設任何對外路由；即使應用層被入侵，資料庫網段也沒有路徑能把資料送出 VPC |
| **ALB（Application Load Balancer）** | 對外流量入口、健康檢查 | 提供單一進入點、支援健康檢查與後續水平擴展 |
| **ECS Fargate** | 執行容器化的 API 服務 | 選擇 Fargate 而非 EC2 模式，免除管理底層主機；相較 EKS 學習曲線較平緩且無控制平面費用 |
| **RDS PostgreSQL** | 資料儲存 | 對應客戶 Oracle → PostgreSQL 的遷移需求，為後續 DMS 遷移演練鋪路 |
| **IAM Role** | 服務間權限控管 | 使用 Role 而非硬編 access key，落實最小權限原則 |
| **Secrets Manager** | 存放資料庫連線資訊 | 避免將帳密寫入程式碼或環境變數；密碼由 Terraform 自動產生，符合企業資安政策 |
| **CloudWatch** | 日誌收集與告警 | AWS 原生整合、基本功能免費，不需額外建 monitoring 基礎架構 |
| **Security Group** | 網路層存取控制 | 明確定義：ALB 僅開 80/443、ECS 僅接受來自 ALB 的流量、RDS 僅接受來自 ECS 的 5432 |

### 5.4 分層安全設計

本專案構想金融業容器平台架構設計的安全策略，安全設計採分層架構，每一層各司其職：

**第一層：網路隔離層**

- VPC 建立獨立網段，不使用 default VPC
- 三層式子網路：Public（ALB、NAT）→ App（ECS）→ Database（RDS），Database 層沒有任何對外路由
- ALB health check 只檢查程式存活（/health/live，不查資料庫），避免資料庫切換時所有 task 被判定不健康而連鎖重啟
- Security Group 明確定義存取規則：ALB 僅開 80/443、ECS 僅接受來自 ALB 的流量、RDS 僅接受來自 ECS 的 5432
- 對應金融業合規的網路分層隔離要求

**第二層：身份與權限層**

- IAM Role 取代硬編 Access Key，服務間採用 Role-based 授權
- 每個服務（ECS Task、Lambda 等）有各自的最小權限 Role，不共用
- 為容器與平台建立專屬的服務身份（IAM Role），並透過該身份授予雲端組件存取權限

**第三層：認證與密鑰管理層**

- Secrets Manager 集中管理資料庫連線資訊，密碼由 Terraform 自動產生（自動輪換列為後續強化項目）
- 認證資訊不進程式碼、不進環境變數，應用服務啟動時動態讀取
- 所有存取行為都有 audit log，稽核時可直接拉報表
- 標準流程：認證資訊寫入 Secrets Manager → 以 Secret 形式注入容器 → 應用服務啟動時讀取

**第四層：變更審查層**

- 所有基礎架構變更必須經過 GitHub PR code review 才能合併
- GitHub Actions 在 PR 階段自動執行 `terraform plan`，合併後才 `terraform apply`
- 變更紀錄完整留存於 Git history，誰改了什麼、為什麼改，全部可追溯

### 5.5 CI/CD Pipeline 設計

本專案的 CI/CD Pipeline 設計涵蓋三個階段：

**CI 階段（持續整合）— 每次 Push / PR 觸發**

```
程式提交 → 程式碼檢查（Lint） → 單元測試 → Docker Build → Push to ECR
```

- 程式碼提交後自動觸發 CI 流程
- 基本的程式碼品質檢查和測試
- 容器鏡像封裝並推送至 ECR

**CD 階段（持續部署）— 合併至 main 時觸發**

```
Terraform Init → Terraform Plan → Terraform Apply → 健康檢查
```

- `terraform plan` 預覽變更內容（PR 階段供 review）
- `terraform apply` 實際部署基礎架構
- 部署後執行健康檢查確認服務正常

**環境關卡設計**

關卡機制的設計原則是：開發階段做程式審查和單元測試，部署階段做版本建置和健康偵測，正式上線前有審核關卡。本專案簡化為：

- PR → 自動跑 `terraform plan` + lint → 人工 code review → 合併
- 合併 main → 自動 `terraform apply` → 健康檢查

### 5.6 分支策略

本專案使用簡化版的 Git Flow 作為分支管理模型：

- **main** — 正式環境的穩定版本，僅透過 PR 合併，合併後自動觸發 `terraform apply`
- **develop** — 開發整合分支，功能開發完成後先合併至此驗證
- **feature/xxx** — 功能分支，從 develop 分出，完成後以 PR 合併回 develop
- **hotfix/xxx** — 緊急修復分支，從 main 分出，修復後同時合併回 main 和 develop

Commit Message 採用 Conventional Commits 規範，格式為 `type(scope): description`，例如：`feat(vpc): add private subnet for RDS`、`fix(sg): correct inbound rule for ECS`。

### 5.7 環境分離策略

金融業常見的環境架構為 DEV/SIT → UAT → PROD，本專案在 Terraform 層面設計環境分離：

```
terraform/
├── bootstrap/            # 建一次、不 destroy：State bucket（S3）、GitHub OIDC Role
├── modules/              # 共用模組：vpc / security_groups / alb / ecs / rds / cloudwatch
└── environments/
    ├── dev/              # 開發環境 — 成本優先
    │   ├── main.tf       # 呼叫 modules（dev / prod 內容完全相同）
    │   ├── variables.tf  #（dev / prod 內容完全相同）
    │   ├── terraform.tfvars   # ← dev 的參數：唯一的差異來源
    │   └── backend.tf    # state 存在 S3 的 dev/
    └── prod/             # 正式環境 — 可用性優先
        ├── main.tf
        ├── variables.tf
        ├── terraform.tfvars   # ← prod 的參數
        ├── drill.tfvars       # 高可用演練專用：關閉刪除保護，演練後可立即 destroy
        └── backend.tf    # state 存在 S3 的 prod/
```

核心原則：**同一份 module，不同參數建出不同環境。** dev 與 prod 的 main.tf、variables.tf 完全相同，所有差異都集中在 terraform.tfvars：

| 參數 | dev（成本優先） | prod（可用性優先） |
|---|---|---|
| `vpc_cidr` | 10.0.0.0/16 | 10.1.0.0/16（不重疊，未來可互連） |
| `nat_mode` | instance（1 台 NAT Instance） | gateway（每 AZ 一台 NAT Gateway） |
| `db_multi_az` | false | true |
| `db_deletion_protection` | false | true |
| `db_skip_final_snapshot` | true | false |
| `db_backup_retention_days` | 1 | 14 |
| `db_apply_immediately` | true | false（等維護時段，避免營業時間重啟） |
| `ecs_min_tasks` / `ecs_max_tasks` | 1 / 2 | 2 / 4 |

variables.tf 刻意不給這些參數預設值，每個環境都必須明確寫出自己的選擇，不會不小心沿用別的環境的設定。個人資訊（告警 email）不進版控：本機放在被 .gitignore 排除的 dev.tfvars / prod.tfvars，CI 從 GitHub Secret 帶入。

PR 時 CI 會同時對 dev 與 prod 跑 `terraform plan`，reviewer 一次看到同一個改動在兩個環境各會產生什麼變更。

### 5.8 認證管理流程

本專案的資料庫認證管理流程如下：

```
1. Terraform 建立 RDS 時，自動產生初始密碼並寫入 Secrets Manager
2. ECS Task Definition 中設定從 Secrets Manager 讀取認證資訊
3. 容器啟動時動態取得 DB 連線資訊，不寫死在 config 或環境變數
4. （後續強化）啟用 Secrets Manager 自動輪換，例如每 90 天
5. 所有存取行為都有 CloudTrail audit log
```

這個流程確保：密碼不進版控、不寫死在任何地方、存取可稽核；下一步啟用自動輪換後，即可滿足定期更換的要求。對應金管會對金融機構的資安要求：「密碼至少每 90 天需更換，未變更密碼帳號應予停用或鎖定」。

### 5.9 監控告警設計

本專案將告警分為「主動告警」和「被動告警」兩類，監控設計如下：

**被動告警（指標閾值觸發）**

透過 CloudWatch Alarm 監控關鍵指標，超過閾值時觸發 SNS 通知：

- ECS CPU 使用率 > 80% → 發送 email 告警
- ECS Memory 使用率 > 80% → 發送 email 告警
- RDS 連線數接近上限 → 發送 email 告警
- ALB 5xx 錯誤率 > 5% → 發送 email 告警

**主動告警（錯誤事件即時通知）**

透過 CloudWatch Logs 的 Metric Filter，偵測應用程式日誌中的錯誤：

- 應用程式拋出未捕獲的 Exception → 即時通知
- 資料庫連線失敗 → 即時通知

**通知管道**

- Phase 1 使用 SNS → Email（最簡單的通知方式）
- 後續可擴展至 Slack Webhook、PagerDuty 等

### 5.10 災難恢復（DR）設計

DR 設計的原則是明確定義 RTO/RPO 指標並定期演練，本專案的 DR 能力建立在 IaC 之上：

**DR 能力**

- `terraform destroy` + `terraform apply` 可從零重建整個環境
- 目標 RTO：< 30 分鐘（基礎架構重建）+ 應用部署時間
- RDS 自動備份 + 跨 AZ 副本提供資料層的 RPO 保障

**DR 演練**

每次執行 `terraform destroy` → `terraform apply` 的循環，本身就是一次 DR 演練。這比傳統企業「備份了但從來沒還原過」的做法更可靠，因為你每次都在驗證重建能力。

簡報時可量化呈現：「我的環境從零重建只要 X 分鐘，這個數字是實際跑過的，不是口頭上的目標。」

### 5.11 應用程式本身

**刻意保持極簡** — 應用程式不是本專案的重點，架構才是。

- **語言／框架**：Python（FastAPI）
- **功能範圍**：交易紀錄查詢服務 API（CRUD + 條件篩選）
- **應用場景**：「IBM 證券交易紀錄查詢服務」— 對應客戶場景，提供交易紀錄的新增、查詢、篩選功能，賦予具體業務場景以便推導架構決策的合理性
- **容器化**：撰寫 Dockerfile，推送至 ECR

**API 設計**

| Endpoint | Method | 功能 |
|---|---|---|
| `/health` | GET | 健康檢查（ALB 用） |
| `/trades` | GET | 列出交易紀錄（支援依帳號、股票代號、日期範圍篩選） |
| `/trades` | POST | 新增交易紀錄 |
| `/trades/{trade_id}` | GET | 查詢單筆交易 |

**資料模型（trades 資料表）**

| 欄位 | 類型 | 說明 |
|---|---|---|
| `trade_id` | UUID | 交易編號（自動產生） |
| `stock_symbol` | VARCHAR | 股票代號（如 2330） |
| `stock_name` | VARCHAR | 股票名稱（如 台積電） |
| `trade_type` | ENUM | 買賣方向（BUY / SELL） |
| `quantity` | INTEGER | 股數 |
| `price` | DECIMAL | 成交價格 |
| `total_amount` | DECIMAL | 成交金額（自動計算） |
| `trade_time` | TIMESTAMP | 交易時間 |
| `account_id` | VARCHAR | 客戶帳號 |
| `status` | ENUM | 交易狀態（pending / completed / cancelled） |

---

## 六、技術棧清單

### 6.1 核心技術

| 類別 | 技術 | 選擇理由 |
|---|---|---|
| **雲端平台** | AWS | 台灣金融業主流雲端平台，符合金管會合規要求 |
| **IaC** | Terraform | 跨雲彈性、社群生態大、人才市場好找人（詳見第四章） |
| **容器** | Docker、ECS Fargate、ECR | 免管底層主機、按使用量計費，適合需求波動場景 |
| **CI/CD** | GitHub Actions | 與 GitHub 深度整合、免費額度充足、設定門檻低 |
| **程式語言** | Python（FastAPI） | 與現有技能相符，可將時間集中在基礎架構學習 |
| **資料庫** | PostgreSQL（RDS） | 對應客戶 Oracle 遷移需求，開源免授權費 |
| **網路** | VPC、Subnet、Security Group、Route Table | 網路隔離是金融業合規的基本要求 |
| **安全** | IAM Role、Secrets Manager | 最小權限原則 + 密碼集中管理 |
| **監控** | CloudWatch（Logs、Metrics、Alarm） | AWS 原生整合、基本功能免費 |
| **版本控制** | Git、GitHub | 業界標準、支援 code review 流程 |

### 6.2 進階技術（後續階段）

| 技術 | 導入時機 | 商業價值 |
|---|---|---|
| **EKS（Kubernetes）** | 第二階段 | 對比 ECS，展示不同容器編排方案的成本與複雜度取捨 |
| **Prometheus + Grafana** | 第二階段 | 跨雲可用的監控方案，降低 vendor lock-in |
| **DMS（資料庫遷移）** | 第三階段 | 對應客戶 Oracle → PostgreSQL 的實際遷移需求 |
| **微服務拆分** | 第三階段 | 展示 monolith → microservices 的遷移路徑 |
| **AWS CDK** | 第三階段（選用） | 與 Terraform 對比，展示 IaC 工具的技術選型分析能力 |

---

## 七、分階段執行計畫

### 第一階段：跑通基礎架構 + 簡報準備（目標：2.5 週）

| 週次 | 任務 | 產出 |
|---|---|---|
| 第 1 週 | 以 Terraform 建置完整架構（VPC → ALB → ECS → RDS → Secrets Manager → CloudWatch） | Terraform code（可 apply／destroy） |
| 第 1-2 週 | 接上 GitHub Actions CI/CD | 自動化部署流程 |
| 第 2-2.5 週 | 準備技術簡報：設計理念、客戶場景、架構決策商業理由 | Presentation 完成 |

> **第一階段的成功標準是「跑通一次 + 簡報完成」。** 若時間不夠，簡報優先於完美的實作。

### 第二階段：容器編排與可觀測性（無時間壓力）

- 將同一服務改以 **EKS** 部署一次，比較 ECS 與 EKS 的差異、成本結構、適用場景
- 導入 **Prometheus + Grafana**（建議先在本地以 Docker Compose 練習）
- 建立實際可用的 dashboard 與告警規則

### 第三階段：進階議題（無時間壓力）

- 使用 **DMS** 進行資料庫遷移演練（Oracle → Aurora PostgreSQL）
- 將單體服務拆分為 2-3 個微服務
- 嘗試以 **AWS CDK** 重寫部分 Terraform，比較兩者差異
- 以 **CodePipeline** 建置一次 CI/CD，與 GitHub Actions 對照

---

## 八、成本控制策略

### 8.1 AWS Free Tier 認知

- **12 個月免費**（新帳號起算）：EC2 t3.micro 750hr/月、RDS db.t3.micro 750hr/月、S3 5GB、ALB 750hr/月
- **永久免費**：Lambda 100 萬次請求/月、DynamoDB 25GB、CloudWatch 基本監控
- 本專案為長期計畫，第 13 個月起 Free Tier 失效，需依賴生命週期管理控制成本

### 8.2 各元件成本風險

| 風險等級 | 元件 | 說明 |
|---|---|---|
| 完全免費 | VPC、Subnet、Security Group、Route Table、IAM | 資源本身不收費，可長期保留 |
| 需注意 | ALB、RDS、ECS Fargate | Free Tier 期間有額度；Fargate 無免費方案 |
| 高風險 | **NAT Gateway** | 約 $0.045/hr + 流量費，24hr 運行月費約 $30-40 美金，無免費額度 |
| 高風險 | **EKS** | 控制平面固定 $0.10/hr（約 $73 美金/月），不論是否有工作負載皆收費 |

### 8.3 控制措施（必做）

1. **設定 Billing Alert** — 於 AWS Budgets 設定 $5 或 $10 預算告警。此項務必第一天就完成。
2. **以 NAT Instance 取代 NAT Gateway** — 自建 t4g.nano 作為 NAT，月費從 $30-40 降到 ~$5。此決策本身即可作為簡報素材，展示成本最佳化思維。
3. **apply / destroy 生命週期管理** — 平時不保留運行中的資源；需驗證或 demo 時才建立，完成後立即銷毀。
4. **EKS 以本地替代** — 使用 kind 或 minikube 在本機練習 Kubernetes 概念（完全免費），僅在需要正式 demo 時才開啟 EKS。
5. **Observability 優先使用 CloudWatch** — 基本功能免費，且為 AWS 原生工具。Prometheus／Grafana 可於本地以 Docker Compose 練習。

---

## 九、簡報準備要點

### 9.1 簡報核心敘事線

```
客戶有這些具體的痛（Persona）
    → 雲端 + IaC 能解決哪些、不能解決哪些（誠實分析）
    → 每個架構元件都對應一個痛點（不是因為酷，是因為解決問題）
    → 每個技術選擇都有成本取捨（不是最好的，是最合理的）
```

### 9.2 簡報設計原則

- 不要高大上的 sales 畫大餅
- Focus 在用雲端這個方式的目的是什麼、可以帶什麼效益
- 要能說清楚「為什麼用 Terraform」「為什麼用 IaC 生命週期管理」「目的和需求是什麼」「架構解決什麼問題」

### 9.3 需同步產出的文件

- **README**：架構圖、元件說明、每個架構決策的理由
- **成本分析**：各方案的成本比較（例如 NAT Gateway vs NAT Instance、ECS vs EKS）
- **踩坑紀錄**：遇到的問題與解法（展現實作深度的重要素材）

---

## 附錄 A：明確排除的技術

以下技術與本專案目標不符，不應納入：

| 技術 | 排除理由 |
|---|---|
| Cloudflare 全家桶（Workers／Pages／D1／R2／KV／Tunnel） | 非 AWS；刻意抽象掉 networking 與 IAM 層 |
| Vercel／Railway／fly.io | 屬輕量型 PaaS，企業級場景不適用 |
| Jenkins | GitHub Actions 已涵蓋 CI/CD 需求，且設定門檻更低 |
| Ansible | 偏地端組態管理，雲原生環境多由 IaC 取代 |
| VMware／Nutanix | 地端機房技術，與「上雲」方向相反 |
