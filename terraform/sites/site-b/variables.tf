variable "aws_region" {
  description = "AWS region for this site"
  type        = string
}

variable "site_name" {
  description = "Logical site name"
  type        = string
  default     = "site-b"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "learning"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zones" {
  description = "Availability zones for the cluster"
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired worker nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum worker nodes"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum worker nodes"
  type        = number
  default     = 4
}

variable "enable_spot_instances" {
  description = "Use spot instances"
  type        = bool
  default     = false
}

variable "mq_client_cidrs" {
  description = "CIDRs allowed to connect to MQ"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "mq_console_cidrs" {
  description = "CIDRs allowed to connect to MQ web console"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default = {
    Owner = "learning-team"
  }
}
