resource "aws_route53_health_check" "primary_tcp" {
  fqdn              = var.primary_nlb_dns_name
  port              = var.health_check_port
  type              = "TCP"
  request_interval  = 30
  failure_threshold = 3

  tags = {
    Name = "mq-primary-health-check"
  }
}

resource "aws_route53_record" "mq_primary" {
  zone_id = var.hosted_zone_id
  name    = var.record_name
  type    = "CNAME"
  ttl     = 30
  records = [var.primary_nlb_dns_name]
  set_identifier = "mq-site-a-primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary_tcp.id
}

resource "aws_route53_record" "mq_secondary" {
  zone_id = var.hosted_zone_id
  name    = var.record_name
  type    = "CNAME"
  ttl     = 30
  records = [var.secondary_nlb_dns_name]
  set_identifier = "mq-site-b-secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }
}
