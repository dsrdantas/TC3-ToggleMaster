variable "argocd_namespace" {
  description = "Namespace do ArgoCD"
  type        = string
  default     = "argocd"
}

variable "gitops_namespace" {
  description = "Namespace das aplicacoes"
  type        = string
  default     = "togglemaster"
}

variable "gitops_repo_url" {
  description = "Repo GitOps monitorado pelo ArgoCD"
  type        = string
}

variable "enable_argocd_apps" {
  description = "Habilita criacao dos Applications/AppProject"
  type        = bool
  default     = false
}

variable "db_password" {
  description = "Senha do PostgreSQL"
  type        = string
  sensitive   = true
}

variable "auth_db_endpoint" {
  description = "Endpoint do Auth DB"
  type        = string
}

variable "flag_db_endpoint" {
  description = "Endpoint do Flag DB"
  type        = string
}

variable "targeting_db_endpoint" {
  description = "Endpoint do Targeting DB"
  type        = string
}

variable "redis_endpoint" {
  description = "Endpoint do Redis"
  type        = string
}

variable "sqs_queue_url" {
  description = "URL da fila SQS"
  type        = string
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

variable "gitops_target_revision" {
  description = "Branch/Tag do repo GitOps"
  type        = string
  default     = "main"
}

variable "gitops_project" {
  description = "Nome do AppProject no ArgoCD"
  type        = string
  default     = "togglemaster"
}

variable "argocd_chart_version" {
  description = "Versao do chart do ArgoCD (opcional)"
  type        = string
  default     = null
}
