###############################################################################
# SSO Permission Sets — provider config
###############################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket         = "acme-lz-terraform-state"
    key            = "permission-sets/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "acme-lz-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region      = var.aws_region
  retry_mode  = "adaptive"
  max_retries = 25

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Component = "sso-permission-sets"
    }
  }
}
