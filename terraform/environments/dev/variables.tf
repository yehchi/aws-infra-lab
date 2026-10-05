# ============================================================
# 變數定義
# 所有可調整的參數都放這裡，實際值放在 dev.tfvars
# ============================================================

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "專案名稱，用於資源命名"
  type        = string
  default     = "aws-infra-lab"
}

variable "environment" {
  description = "環境名稱（dev / prod）"
  type        = string
  default     = "dev"
}

# ----- VPC -----
variable "vpc_cidr" {
  description = "VPC 的 CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public Subnet 的 CIDR blocks（跨 2 個 AZ）"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private Subnet 的 CIDR blocks（跨 2 個 AZ）"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "availability_zones" {
  description = "使用的 Availability Zones"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

# ----- RDS -----
variable "db_instance_class" {
  description = "RDS instance 規格"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "資料庫名稱"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "資料庫管理員帳號"
  type        = string
  default     = "dbadmin"
}

# ----- CloudWatch -----
variable "alert_email" {
  description = "告警通知 email"
  type        = string
}
