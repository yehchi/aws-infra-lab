variable "project_name" {
  description = "專案名稱"
  type        = string
}

variable "environment" {
  description = "環境名稱"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet IDs（RDS 放這裡）"
  type        = list(string)
}

variable "rds_sg_id" {
  description = "RDS Security Group ID"
  type        = string
}

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
