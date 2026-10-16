# ============================================================
# Batch Module — 收盤後批次作業
#
#   EventBridge Scheduler（每個交易日收盤後）
#     → Step Functions：日終結算 → 交割作業 → 法規報表
#         每一步都是一個 ECS Fargate 排程任務：跑完即結束，只為執行時間付費
#     → 任一步驟重試後仍失敗：執行停在該步驟（可從中斷處 redrive 續跑）
#                            並由 EventBridge 規則發 SNS 告警
#
# 重用現有架構：同一個 ECS cluster、同一個 image、同一個 App 層 subnet 與 Security Group
# ============================================================

data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  # SSM 參數名稱不能以 aws / ssm 開頭（AWS 保留字），所以不用 project_name（aws-infra-lab）當前綴
  param_prefix = "/infra-lab/${var.environment}/batch"
}

# ----- 演練開關（SSM Parameter Store）-----
# 平常都是預設值，批次正常執行；演練時用 aws ssm put-parameter 修改，不用改程式或重新部署
resource "aws_ssm_parameter" "fail_step" {
  name        = "${local.param_prefix}/fail-step"
  description = "演練用：設成 settlement / clearing / report 即在該步驟模擬失敗；none = 正常"
  type        = "String"
  value       = "none"

  lifecycle {
    ignore_changes = [value] # 演練時會手動修改，Terraform 不要改回來
  }
}

resource "aws_ssm_parameter" "report_load_seconds" {
  name        = "${local.param_prefix}/report-load-seconds"
  description = "演練用：報表步驟額外對讀取端施加 N 秒重查詢，模擬大型報表；0 = 不施壓"
  type        = "String"
  value       = "0"

  lifecycle {
    ignore_changes = [value]
  }
}

# ----- 批次任務的 IAM Role（容器裡的程式用）-----
# 最小權限：只能讀自己的兩個演練開關
resource "aws_iam_role" "batch_task" {
  name = "${local.name_prefix}-batch-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "batch_task" {
  name = "${local.name_prefix}-batch-task-ssm"
  role = aws_iam_role.batch_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = [aws_ssm_parameter.fail_step.arn, aws_ssm_parameter.report_load_seconds.arn]
    }]
  })
}

# ----- 批次任務定義：同一個 image，啟動指令由 Step Functions 每一步覆寫 -----
resource "aws_ecs_task_definition" "batch" {
  family                   = "${local.name_prefix}-batch"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = aws_iam_role.batch_task.arn

  container_definitions = jsonencode([{
    name      = "batch"
    image     = "${var.ecr_repository_url}:latest" # 跟線上服務同一份 image，每次部署自動更新
    essential = true
    command   = ["python", "-m", "batch.run", "settlement"]

    environment = [
      { name = "DRILL_PARAM_PREFIX", value = local.param_prefix }
    ]

    secrets = [
      { name = "DB_HOST", valueFrom = "${var.db_secret_arn}:host::" },
      { name = "DB_READ_HOST", valueFrom = "${var.db_secret_arn}:read_host::" },
      { name = "DB_PORT", valueFrom = "${var.db_secret_arn}:port::" },
      { name = "DB_NAME", valueFrom = "${var.db_secret_arn}:dbname::" },
      { name = "DB_USER", valueFrom = "${var.db_secret_arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.log_group_name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "batch"
      }
    }
  }])
}

# ----- Step Functions：結算 → 交割 → 報表 -----
locals {
  network = {
    AwsvpcConfiguration = {
      Subnets        = var.app_subnet_ids
      SecurityGroups = [var.ecs_sg_id]
      AssignPublicIp = "DISABLED"
    }
  }

  # 每一步：跑一個 ECS 任務並等它結束（.sync），失敗自動重試 1 次
  steps = {
    Settlement = { cmd = "settlement", next = "Clearing", comment = "日終結算：成交依帳戶、股票彙總" }
    Clearing   = { cmd = "clearing", next = "Report", comment = "交割作業：產生 T+2 交割款項" }
    Report     = { cmd = "report", next = "Done", comment = "法規報表：讀 Read Replica 產生當日報表" }
  }

  step_states = {
    for name, s in local.steps : name => {
      Type     = "Task"
      Comment  = s.comment
      Resource = "arn:aws:states:::ecs:runTask.sync"
      Parameters = {
        Cluster              = var.cluster_arn
        TaskDefinition       = aws_ecs_task_definition.batch.family # 用 family = 永遠跑最新版
        LaunchType           = "FARGATE"
        NetworkConfiguration = local.network
        Overrides = {
          ContainerOverrides = [{
            Name    = "batch"
            Command = ["python", "-m", "batch.run", s.cmd]
            Environment = [
              { Name = "TRADE_DATE", "Value.$" = "$.trade_date" }
            ]
          }]
        }
      }
      ResultPath     = null # 不把 ECS 回傳的大段資料塞進狀態，下一步只需要 trade_date
      TimeoutSeconds = 1800
      Retry = [{
        ErrorEquals     = ["States.ALL"]
        IntervalSeconds = 30
        MaxAttempts     = 1
        BackoffRate     = 2
      }]
      Next = s.next
    }
  }

  definition = {
    Comment = "IBM 證券收盤後批次：日終結算 → 交割作業 → 法規報表"
    StartAt = "CheckTradeDate"
    States = merge({
      # 排程觸發時沒有帶日期 → 用執行開始時間的日期（收盤後 14:30 台灣 = 06:30 UTC，同一天）
      # 手動補跑時可以在 input 指定 {"trade_date": "YYYY-MM-DD"}
      CheckTradeDate = {
        Type    = "Choice"
        Choices = [{ Variable = "$.trade_date", IsPresent = true, Next = "Settlement" }]
        Default = "SetTradeDate"
      }
      SetTradeDate = {
        Type = "Pass"
        Parameters = {
          "trade_date.$" = "States.ArrayGetItem(States.StringSplit($$.Execution.StartTime, 'T'), 0)"
        }
        Next = "Settlement"
      }
      Done = { Type = "Succeed" }
    }, local.step_states)
  }
}

resource "aws_iam_role" "sfn" {
  name = "${local.name_prefix}-batch-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn" {
  name = "${local.name_prefix}-batch-sfn"
  role = aws_iam_role.sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # 只能啟動批次這一個 task definition 的任務
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = ["${aws_ecs_task_definition.batch.arn_without_revision}:*"]
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:StopTask", "ecs:DescribeTasks"]
        Resource = ["*"]
      },
      {
        # 啟動任務時要把兩個角色交給 ECS
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [var.task_execution_role_arn, aws_iam_role.batch_task.arn]
      },
      {
        # .sync 模式需要：Step Functions 用 EventBridge 規則接收 ECS 任務結束的事件
        Effect   = "Allow"
        Action   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
        Resource = ["arn:aws:events:${data.aws_region.current.name}:*:rule/StepFunctionsGetEventsForECSTaskRule"]
      }
    ]
  })
}

resource "aws_sfn_state_machine" "batch" {
  name       = "${local.name_prefix}-eod-batch"
  role_arn   = aws_iam_role.sfn.arn
  definition = jsonencode(local.definition)
  type       = "STANDARD" # 標準型才能從中斷步驟 redrive、保留 90 天執行紀錄
}

# ----- EventBridge Scheduler：每個交易日收盤後觸發 -----
resource "aws_iam_role" "scheduler" {
  name = "${local.name_prefix}-batch-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${local.name_prefix}-batch-scheduler"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = [aws_sfn_state_machine.batch.arn]
    }]
  })
}

resource "aws_scheduler_schedule" "eod" {
  name        = "${local.name_prefix}-eod-batch"
  description = "收盤後批次（台股 13:30 收盤，14:30 開始）"

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "Asia/Taipei"
  state                        = var.schedule_enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.batch.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({}) # 不帶日期 → 狀態機自動用當天
  }
}

# ----- 失敗告警：批次執行失敗 / 逾時 → SNS（沿用既有告警管道）-----
resource "aws_cloudwatch_event_rule" "batch_failed" {
  name        = "${local.name_prefix}-batch-failed"
  description = "收盤後批次執行失敗時通知維運人員"

  event_pattern = jsonencode({
    source        = ["aws.states"]
    "detail-type" = ["Step Functions Execution Status Change"]
    detail = {
      stateMachineArn = [aws_sfn_state_machine.batch.arn]
      status          = ["FAILED", "TIMED_OUT", "ABORTED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "batch_failed_sns" {
  rule = aws_cloudwatch_event_rule.batch_failed.name
  arn  = var.sns_topic_arn

  input_transformer {
    input_paths = {
      name   = "$.detail.name"
      status = "$.detail.status"
      time   = "$.time"
    }
    input_template = "\"【批次告警】收盤後批次執行 <status>（執行名稱 <name>，時間 <time> UTC）。請到 Step Functions 查看失敗步驟，修正後可從中斷處 Redrive 續跑。\""
  }
}
