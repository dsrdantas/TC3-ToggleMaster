variable "aws_region" {
  description = "Regiao AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "togglemaster"
}

variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "cluster_version" {
  description = "Versao do Kubernetes"
  type        = string
  default     = "1.35"
}

variable "node_instance_types" {
  description = "Tipos de instancia para os nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Numero desejado de nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Numero minimo de nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Numero maximo de nodes"
  type        = number
  default     = 4
}

variable "node_capacity_type" {
  description = "Tipo de capacidade dos nodes (ON_DEMAND ou SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_ami_type" {
  description = "Tipo de AMI do node group (ex: AL2023_x86_64_STANDARD, BOTTLEROCKET_x86_64)"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_disk_size" {
  description = "Tamanho do disco dos nodes (GiB)"
  type        = number
  default     = 20
}

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks das subnets publicas"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks das subnets privadas"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.22.0/24"]
}

variable "availability_zones" {
  description = "Zonas de disponibilidade"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "lab_role_arn" {
  description = "ARN da LabRole (AWS Academy)"
  type        = string
}

variable "db_password" {
  description = "Senha do PostgreSQL"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "Usuario do PostgreSQL"
  type        = string
  default     = "tm_user"
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

variable "queue_name" {
  description = "Nome da fila SQS"
  type        = string
  default     = "dsrdantas-queue"
}

variable "visibility_timeout" {
  description = "Timeout de visibilidade da mensagem (segundos)"
  type        = number
  default     = 30
}

variable "message_retention" {
  description = "Retencao da mensagem (segundos)"
  type        = number
  default     = 86400
}

variable "ecr_repository_names" {
  description = "Nomes dos repositorios ECR"
  type        = list(string)
  default     = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service"
  ]
}

variable "aws_access_key_id" {
  description = "AWS Access Key ID (AWS Academy)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key (AWS Academy)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_session_token" {
  description = "AWS Session Token (AWS Academy)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "service_api_key" {
  description = "API key de servico (evaluation-service)"
  type        = string
  default     = "PLACEHOLDER_GERAR_DEPOIS"
  sensitive   = true
}

variable "master_key" {
  description = "Master key do auth-service (opcional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  description = "Tags globais para todos os recursos"
  type        = map(string)
  default = {
    Project     = "ToggleMaster"
    Environment = "production"
    ManagedBy   = "terraform"
    Phase       = "3"
  }
}

variable "gitops_repo_url" {
  description = "URL do repositorio GitOps"
  type        = string
}

variable "enable_apps" {
  description = "Habilita instalacao do ArgoCD + apps + secrets"
  type        = bool
  default     = false
}

variable "enable_argocd_apps" {
  description = "Habilita criacao dos Applications/AppProject do ArgoCD"
  type        = bool
  default     = false
}
