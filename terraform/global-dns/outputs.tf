output "mq_client_fqdn" {
  description = "Client endpoint with Route53 failover routing"
  value       = var.record_name
}

output "primary_health_check_id" {
  description = "Primary endpoint health check ID"
  value       = aws_route53_health_check.primary_tcp.id
}
