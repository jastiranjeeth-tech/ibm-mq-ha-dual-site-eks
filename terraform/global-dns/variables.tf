variable "aws_region" {
  description = "Route53 control plane region (any commercial region)"
  type        = string
  default     = "us-east-1"
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "record_name" {
  description = "FQDN used by MQ clients (e.g., mq.example.com)"
  type        = string
}

variable "primary_nlb_dns_name" {
  description = "Site A NLB DNS name"
  type        = string
}

variable "secondary_nlb_dns_name" {
  description = "Site B NLB DNS name"
  type        = string
}

variable "health_check_port" {
  description = "Port checked on primary endpoint"
  type        = number
  default     = 1414
}
