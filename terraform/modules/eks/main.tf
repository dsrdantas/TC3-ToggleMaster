resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = var.lab_role_arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  tags = merge(var.tags, {
    Name = var.cluster_name
  })
}
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-ng"
  node_role_arn   = var.lab_role_arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.node_instance_types
  capacity_type   = var.node_capacity_type
  ami_type        = var.node_ami_type
  disk_size       = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-ng"
  })

  depends_on = [aws_eks_cluster.main]
}
