###############################################################################
# sfn-pipeline — providers + backend config
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
    key            = "sfn-pipeline/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "acme-lz-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region     = var.region
  retry_mode = "adaptive"

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Component   = "sfn-pipeline"
      Environment = "management"
    }
  }
}
