################################################################################
# Landing Zone Orchestration - Providers
################################################################################
# Management account provider + dynamic target account providers
# This layer is applied from the management account.
################################################################################

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
    key            = "landing-zone/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "acme-lz-terraform-locks"
    encrypt        = true
  }
}

# ── Management Account Provider ──────────────────────────────────────────────
provider "aws" {
  region      = var.primary_region
  retry_mode  = "adaptive"
  max_retries = 25

  default_tags {
    tags = local.common_tags
  }
}
