###############################################################################
# main.tf - Provider & backend configuration
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Uncomment and configure for remote state in a real deployment
  # backend "s3" {
  #   bucket = "my-terraform-state-bucket"
  #   key    = "auto-healing-ecs/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "auto-healing-ecs-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Convenience data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}
