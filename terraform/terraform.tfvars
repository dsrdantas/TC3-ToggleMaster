# Copie este arquivo para terraform.tfvars e preencha os valores
# cp terraform.tfvars.example terraform.tfvars

aws_region   = "us-east-1"
project_name = "togglemaster"
cluster_name = "togglemaster-cluster"
cluster_version     = "1.35"
node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 4
node_capacity_type  = "SPOT"
node_ami_type       = "AL2023_x86_64_STANDARD"
node_disk_size      = 20
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.22.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b"]

# AWS Academy - ARN da LabRole (substitua pelo seu)
lab_role_arn = "arn:aws:iam::381492315995:role/LabRole"

# Senha do PostgreSQL (substitua por uma senha forte)
db_password = "381492315995"
db_username = "tm_user"
db_instance_class   = "db.t3.micro"
db_allocated_storage = 20
db_engine_version   = "17.4"
db_storage_type     = "gp3"
db_publicly_accessible = false
db_skip_final_snapshot = true
redis_node_type     = "cache.t3.micro"
dynamodb_table_name = "ToggleMasterAnalytics"
queue_name          = "togglemaster-queue"
visibility_timeout  = 30
message_retention   = 86400
ecr_repository_names = [
  "auth-service",
  "flag-service",
  "targeting-service",
  "evaluation-service",
  "analytics-service"
]

# Repo GitOps (monorepo)
gitops_repo_url = "https://github.com/dsrdantas/TC3-ToggleMaster.git"

# Credenciais AWS (opcional; se vazio, usa env vars no setup)
aws_access_key_id     = ""
aws_secret_access_key = ""
aws_session_token     = ""

# ArgoCD Apps (usado pelo setup-full para aplicar em duas etapas)
enable_argocd_apps    = false
enable_apps = true