variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "learning"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "mq-ha-learning-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for the cluster"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium" # 2 vCPU, 4GB RAM - cost effective
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "enable_spot_instances" {
  description = "Use spot instances for additional cost savings"
  type        = bool
  default     = false # Set to true for ~70% cost reduction (with interruption risk)
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default = {
    Owner = "learning-team"
  }
}
