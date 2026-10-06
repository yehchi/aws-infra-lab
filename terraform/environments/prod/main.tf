# ============================================================
# 環境主設定檔（dev / prod 的 main.tf 內容完全相同）
#
# 兩個環境呼叫同一份 module，所有差異都在 terraform.tfvars：
#   diff terraform/environments/dev/terraform.tfvars terraform/environments/prod/terraform.tfvars
# ============================================================

# ----- 網路：三層式 VPC -----
module "vpc" {
  source = "../../modules/vpc"

  project_name        = var.project_name
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
  app_subnet_cidrs    = var.app_subnet_cidrs
  db_subnet_cidrs     = var.db_subnet_cidrs
  nat_mode            = var.nat_mode
}

# ----- Security Groups：ALB → ECS → RDS 逐層放行 -----
module "security_groups" {
  source = "../../modules/security_groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
}

# ----- ALB -----
module "alb" {
  source = "../../modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id
}

# ----- RDS -----
module "rds" {
  source = "../../modules/rds"

  project_name                = var.project_name
  environment                 = var.environment
  db_subnet_ids               = module.vpc.db_subnet_ids
  rds_sg_id                   = module.security_groups.rds_sg_id
  db_instance_class           = var.db_instance_class
  db_name                     = var.db_name
  db_username                 = var.db_username
  multi_az                    = var.db_multi_az
  deletion_protection         = var.db_deletion_protection
  skip_final_snapshot         = var.db_skip_final_snapshot
  backup_retention_days       = var.db_backup_retention_days
  apply_immediately           = var.db_apply_immediately
  secret_recovery_window_days = var.secret_recovery_window_days
}

# ----- ECS Fargate + Auto Scaling -----
module "ecs" {
  source = "../../modules/ecs"

  project_name       = var.project_name
  environment        = var.environment
  app_subnet_ids     = module.vpc.app_subnet_ids
  ecs_sg_id          = module.security_groups.ecs_sg_id
  target_group_arn   = module.alb.target_group_arn
  db_secret_arn      = module.rds.secret_arn
  min_tasks          = var.ecs_min_tasks
  max_tasks          = var.ecs_max_tasks
  cpu_target_percent = var.ecs_cpu_target_percent
}

# ----- CloudWatch 告警 -----
module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project_name     = var.project_name
  environment      = var.environment
  alert_email      = var.alert_email
  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.ecs.service_name
  alb_arn_suffix   = module.alb.alb_arn_suffix
  rds_instance_id  = module.rds.db_instance_id
}
