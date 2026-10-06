# ============================================================
# ECS Module
# ECR（存 Docker image）+ ECS Fargate（跑容器）+ IAM Role
# ============================================================

# ----- 取得目前的 AWS Account ID 和 Region -----
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ----- ECR Repository -----
# 存放 Docker image 的地方（類似私有的 Docker Hub）
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-${var.environment}-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # dev 環境允許直接刪除（含 images）

  image_scanning_configuration {
    scan_on_push = true # 每次 push image 自動掃描漏洞
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app"
  }
}

# ----- ECS Cluster -----
# Fargate 的容器都跑在這個 cluster 裡
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled" # 啟用 Container Insights 監控
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cluster"
  }
}

# ----- CloudWatch Log Group for ECS -----
# 容器的 stdout/stderr 會送到這裡
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = 7 # dev 環境只保留 7 天

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-logs"
  }
}

# ----- ECS Task Execution Role -----
# ECS 服務本身需要的權限（拉 image、寫 log、讀 secret）
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-${var.environment}-ecs-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-exec-role"
  }
}

# 附加 AWS 預設的 ECS 執行策略
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 允許讀取 Secrets Manager（拿 DB 密碼用）
resource "aws_iam_role_policy" "ecs_secrets" {
  name = "${var.project_name}-${var.environment}-ecs-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [var.db_secret_arn]
      }
    ]
  })
}

# ----- ECS Task Role -----
# 容器裡的應用程式需要的權限（目前最小權限，之後按需增加）
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-task-role"
  }
}

# ----- ECS Task Definition -----
# 定義容器怎麼跑：用哪個 image、多少 CPU/記憶體、環境變數
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-${var.environment}-app"
  network_mode             = "awsvpc" # Fargate 必須用 awsvpc
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # 0.25 vCPU
  memory                   = "512" # 512 MB
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "app"
      image = "${aws_ecr_repository.app.repository_url}:latest"

      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]

      # 從 Secrets Manager 讀取 DB 連線資訊
      secrets = [
        {
          name      = "DB_HOST"
          valueFrom = "${var.db_secret_arn}:host::"
        },
        {
          name      = "DB_PORT"
          valueFrom = "${var.db_secret_arn}:port::"
        },
        {
          name      = "DB_NAME"
          valueFrom = "${var.db_secret_arn}:dbname::"
        },
        {
          name      = "DB_USER"
          valueFrom = "${var.db_secret_arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.db_secret_arn}:password::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "app"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-app-task"
  }
}

# ----- ECS Service -----
# 確保永遠至少有 min_tasks 個容器在跑，task 會自動分散到兩個 AZ 的 App 層 subnet
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-${var.environment}-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.min_tasks
  launch_type     = "FARGATE"

  # 新 task 啟動後的寬限期：這段時間內 ALB health check 失敗不會被判定為故障
  # 容器 image 事先 build 好、啟動只需幾秒，所以寬限期可以設得短
  health_check_grace_period_seconds = var.health_check_grace_period

  # 滾動部署：先起新版、確認健康後才停舊版，部署過程服務不中斷
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # 部署失敗自動回滾：新版 task 一直起不來（例如 image 有 bug）時，自動退回上一版
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false # App 層沒有 Public IP，只能經 NAT 主動對外
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "app"
    container_port   = 8000
  }

  lifecycle {
    ignore_changes = [
      task_definition, # 由 CI/CD 部署新版，不由 Terraform 管
      desired_count,   # 由 Auto Scaling 調整，不由 Terraform 管
    ]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-service"
  }
}

# ============================================================
# Auto Scaling：依 CPU 使用率自動增減 task 數量
# 對應結算日負載 3-5 倍的情境：尖峰自動擴展、離峰自動縮回
# ============================================================

resource "aws_appautoscaling_target" "ecs" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "${var.project_name}-${var.environment}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.cpu_target_percent # 平均 CPU 維持在這個數字附近
    scale_out_cooldown = 60                     # 擴展反應要快
    scale_in_cooldown  = 180                    # 縮減要保守，避免來回震盪
  }
}
