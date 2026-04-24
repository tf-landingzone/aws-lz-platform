###############################################################################
# Account Setup — provider config
###############################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Remote state — key set per-account via CLI:
  #   terraform init -backend-config="key=account-setup/<ACCOUNT_ID>/terraform.tfstate"
  backend "s3" {
    bucket         = "acme-lz-terraform-state"
    region         = "us-east-1"
    dynamodb_table = "acme-lz-terraform-locks"
    encrypt        = true
  }
}

# ── Management / delegated-admin account (SSO + Organizations) ───────────────
provider "aws" {
  region      = var.aws_region
  retry_mode  = "adaptive"
  max_retries = 25

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Component = "account-setup"
    }
  }
}

# ── Target account — assumed via Control Tower execution role ─────────────────
provider "aws" {
  alias       = "target"
  region      = var.aws_region
  retry_mode  = "adaptive"
  max_retries = 25

  assume_role {
    role_arn     = "arn:aws:iam::${var.account_id}:role/${var.assume_role_name}"
    session_name = "tf-account-setup"
    external_id  = var.account_id
  }

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Component = "account-setup"
    }
  }
}
