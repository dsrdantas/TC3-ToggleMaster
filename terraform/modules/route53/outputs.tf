output "zone_id" {
  description = "ID da hosted zone"
  value       = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "Name servers para apontar no registrar"
  value       = aws_route53_zone.this.name_servers
}
