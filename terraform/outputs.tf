output "vpc_id" {
  description = "ID da VPC"
  value       = module.networking.vpc_id
}
output "eks_cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "route53_zone_id" {
  description = "ID da hosted zone do Route53"
  value       = var.enable_route53 ? module.route53[0].zone_id : ""
}

output "route53_name_servers" {
  description = "Name servers para apontar no registrar externo"
  value       = var.enable_route53 ? module.route53[0].name_servers : []
}

output "eks_cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  value       = module.eks.cluster_endpoint
}
output "auth_db_endpoint" {
  description = "Endpoint do Auth DB"
  value       = module.databases.auth_db_endpoint
}

output "flag_db_endpoint" {
  description = "Endpoint do Flag DB"
  value       = module.databases.flag_db_endpoint
}

output "targeting_db_endpoint" {
  description = "Endpoint do Targeting DB"
  value       = module.databases.targeting_db_endpoint
}

output "redis_endpoint" {
  description = "Endpoint do Redis"
  value       = module.databases.redis_endpoint
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB"
  value       = module.databases.dynamodb_table_name
}
output "sqs_queue_url" {
  description = "URL da fila SQS"
  value       = module.messaging.queue_url
}
output "ecr_repository_urls" {
  description = "URLs dos repositorios ECR"
  value       = module.ecr.repository_urls
}
