# ============================================================
# ALB Module
# Application Load Balancer — 對外流量的唯一入口
# 外部請求 → ALB (80) → Target Group → ECS Fargate (8000)
# ============================================================

# ----- ALB 本體 -----
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false # 對外（internet-facing）
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-alb"
  }
}

# ----- Target Group -----
# ALB 把流量轉發到這個 group 裡的 ECS tasks
resource "aws_lb_target_group" "ecs" {
  name        = "${var.project_name}-${var.environment}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Fargate 用 ip 模式，不是 instance

  # task 下線前，等進行中的請求跑完的時間（預設 300 秒）
  # API 請求都是毫秒級，30 秒綽綽有餘；縮短可加快部署與故障替換
  deregistration_delay = var.deregistration_delay

  # Health check 只檢查「程式本身活著」（/health/live，不查資料庫）
  # 若改查資料庫，DB 故障切換時所有 task 會同時被判定不健康而全部重建（連鎖故障）
  #
  # 偵測時間 ≈ interval × unhealthy_threshold
  # 容器 image 事先 build 好、啟動只需幾秒，可以用比較緊的參數快速發現故障
  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = 5
    interval            = var.health_check_interval
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-tg"
  }
}

# ----- Listener -----
# 監聽 port 80，把流量轉給 Target Group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }
}
