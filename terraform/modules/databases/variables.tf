variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs das subnets privadas"
  type        = list(string)
}

variable "rds_sg_id" {
  description = "ID do security group do RDS"
  type        = string
}

variable "redis_sg_id" {
  description = "ID do security group do Redis"
  type        = string
}

variable "db_username" {
  description = "Usuario do PostgreSQL"
  type        = string
  default     = "tm_user"
}

variable "db_password" {
  description = "Senha do PostgreSQL"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "Classe da instancia RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Storage das instancias RDS (GiB)"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "Versao do engine PostgreSQL"
  type        = string
  default     = "17.4"
}

variable "db_storage_type" {
  description = "Tipo de storage do RDS (gp2, gp3, io1, etc.)"
  type        = string
  default     = "gp2"
}

variable "db_publicly_accessible" {
  description = "RDS acessivel publicamente"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Pular snapshot final ao destruir RDS"
  type        = bool
  default     = true
}

variable "redis_node_type" {
  description = "Tipo do node ElastiCache"
  type        = string
  default     = "cache.t3.micro"
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB"
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "tags" {
  description = "Tags adicionais"
  type        = map(string)
  default     = {}
}
