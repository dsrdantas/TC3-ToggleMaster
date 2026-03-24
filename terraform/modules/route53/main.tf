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

resource "aws_route53_record" "records" {
  for_each = {
    for idx, record in var.records : tostring(idx) => record
  }

  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records
}
