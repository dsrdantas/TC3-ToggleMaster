module "networking" {
  source = "./modules/networking"

  project_name = var.project_name
  cluster_name = var.cluster_name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones  = var.availability_zones
  tags         = var.tags
}
module "eks" {
  source = "./modules/eks"

  project_name      = var.project_name
  cluster_name      = var.cluster_name
  cluster_version   = var.cluster_version
  subnet_ids        = module.networking.private_subnet_ids
  security_group_id = module.networking.eks_nodes_sg_id
  lab_role_arn      = var.lab_role_arn
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_capacity_type  = var.node_capacity_type
  node_ami_type       = var.node_ami_type
  node_disk_size      = var.node_disk_size
  tags              = var.tags
}
module "databases" {
  source = "./modules/databases"

  project_name       = var.project_name
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.networking.rds_sg_id
  redis_sg_id        = module.networking.redis_sg_id
  db_username        = var.db_username
  db_password        = var.db_password
  db_instance_class  = var.db_instance_class
  db_allocated_storage = var.db_allocated_storage
  db_engine_version    = var.db_engine_version
  db_storage_type      = var.db_storage_type
  db_publicly_accessible = var.db_publicly_accessible
  db_skip_final_snapshot = var.db_skip_final_snapshot
  redis_node_type    = var.redis_node_type
  dynamodb_table_name = var.dynamodb_table_name
  tags               = var.tags
}
module "messaging" {
  source = "./modules/messaging"

  project_name = var.project_name
  queue_name   = var.queue_name
  visibility_timeout = var.visibility_timeout
  message_retention  = var.message_retention
  tags         = var.tags
}
module "ecr" {
  source = "./modules/ecr"

  repository_names = var.ecr_repository_names
  tags = var.tags
}
module "apps" {
  source = "./modules/apps"
  count  = var.enable_apps ? 1 : 0

  enable_argocd_apps = var.enable_argocd_apps
  gitops_repo_url = var.gitops_repo_url
  db_password     = var.db_password
  auth_db_endpoint      = module.databases.auth_db_endpoint
  flag_db_endpoint      = module.databases.flag_db_endpoint
  targeting_db_endpoint = module.databases.targeting_db_endpoint
  redis_endpoint        = module.databases.redis_endpoint
  sqs_queue_url         = module.messaging.queue_url
  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
  aws_session_token     = var.aws_session_token
  service_api_key       = var.service_api_key
  master_key            = var.master_key

  providers = {
    kubernetes = kubernetes
    helm       = helm
  }

  depends_on = [module.eks]
}
resource "aws_security_group_rule" "rds_from_eks_cluster_sg" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = module.eks.cluster_security_group_id
  security_group_id        = module.networking.rds_sg_id
  description              = "PostgreSQL from EKS cluster SG"
}

resource "aws_security_group_rule" "redis_from_eks_cluster_sg" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = module.eks.cluster_security_group_id
  security_group_id        = module.networking.redis_sg_id
  description              = "Redis from EKS cluster SG"
}
