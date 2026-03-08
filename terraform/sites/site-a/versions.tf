terraform {
  required_version = ">= 1.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "MQ-HA-Dual-Site"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Site        = var.site_name
    }
  }
}
