resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-rds-subnet-group"
  })
}
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-redis-subnet-group"
  })
}
resource "aws_db_instance" "auth" {
  identifier     = "${var.project_name}-auth-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = var.db_storage_type

  db_name  = "auth_db"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = var.db_publicly_accessible
  skip_final_snapshot    = var.db_skip_final_snapshot

  lifecycle {
    ignore_changes = [storage_type]
  }

  tags = merge(var.tags, {
    Name    = "${var.project_name}-auth-db"
    Service = "auth-service"
  })
}
resource "aws_db_instance" "flag" {
  identifier     = "${var.project_name}-flag-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = var.db_storage_type

  db_name  = "flag_db"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = var.db_publicly_accessible
  skip_final_snapshot    = var.db_skip_final_snapshot

  lifecycle {
    ignore_changes = [storage_type]
  }

  tags = merge(var.tags, {
    Name    = "${var.project_name}-flag-db"
    Service = "flag-service"
  })
}
resource "aws_db_instance" "targeting" {
  identifier     = "${var.project_name}-targeting-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = var.db_storage_type

  db_name  = "targeting_db"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  publicly_accessible    = var.db_publicly_accessible
  skip_final_snapshot    = var.db_skip_final_snapshot

  lifecycle {
    ignore_changes = [storage_type]
  }

  tags = merge(var.tags, {
    Name    = "${var.project_name}-targeting-db"
    Service = "targeting-service"
  })
}
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [var.redis_sg_id]

  tags = merge(var.tags, {
    Name    = "${var.project_name}-redis"
    Service = "evaluation-service"
  })
}
resource "aws_dynamodb_table" "analytics" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = merge(var.tags, {
    Name    = var.dynamodb_table_name
    Service = "analytics-service"
  })
}
