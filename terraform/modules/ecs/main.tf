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
  cpu                      = "256"  # 0.25 vCPU
  memory                   = "512"  # 512 MB
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
# 確保永遠有指定數量的容器在跑
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-${var.environment}-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1 # dev 環境跑 1 個就好
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false # 在 Private Subnet，透過 NAT 連外網
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "app"
    container_port   = 8000
  }

  # 第一次部署時 ECR 還沒有 image，所以忽略 task_definition 的變更
  # 等 CI/CD push image 後再更新
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-service"
  }
}
