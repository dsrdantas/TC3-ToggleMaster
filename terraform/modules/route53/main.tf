resource "aws_route53_zone" "this" {
  name          = var.domain_name
  comment       = var.comment
  force_destroy = var.force_destroy

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-zone"
    }
  )
}
