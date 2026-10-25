terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Partial config: bucket/table/region come from backend.hcl (written by bootstrap/bootstrap.sh)
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "sentimentops"
      Owner     = "shaurya"
      ManagedBy = "terraform"
    }
  }
}
