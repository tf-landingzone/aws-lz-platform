###############################################################################
# 00-bootstrap — Shared naming, tags, backend resources
###############################################################################
# Apply FIRST. Creates the S3 + DynamoDB state backend and defines shared
# naming/tagging conventions used by all other stacks.
###############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = local.common_tags
  }
}

# ── Naming ───────────────────────────────────────────────────────────────────
locals {
  prefix = "${var.org}-${var.program}"

  common_tags = merge({
    Org        = var.org
    Program    = var.program
    Owner      = var.owner
    CostCenter = var.cost_center
    ManagedBy  = "terraform"
  }, var.extra_tags)
}

# ── State Backend — S3 Bucket ────────────────────────────────────────────────
resource "aws_s3_bucket" "state" {
  count  = var.create_state_backend ? 1 : 0
  bucket = "${local.prefix}-terraform-state"

  tags = { Name = "${local.prefix}-terraform-state" }
}

resource "aws_s3_bucket_versioning" "state" {
  count  = var.create_state_backend ? 1 : 0
  bucket = aws_s3_bucket.state[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  count  = var.create_state_backend ? 1 : 0
  bucket = aws_s3_bucket.state[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  count  = var.create_state_backend ? 1 : 0
  bucket = aws_s3_bucket.state[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── State Backend — DynamoDB Lock Table ──────────────────────────────────────
resource "aws_dynamodb_table" "lock" {
  count        = var.create_state_backend ? 1 : 0
  name         = "${local.prefix}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "${local.prefix}-terraform-locks" }
}

# ── Deploy Run State — DynamoDB table for resume-on-failure ──────────────────
# Used by scripts/deploy_accounts.py --run-id / --resume.
# PK=run_id (S), SK=account_id (S).  Items expire after 14 days via TTL.
resource "aws_dynamodb_table" "deploy_run_state" {
  count        = var.create_state_backend ? 1 : 0
  name         = "${local.prefix}-deploy-run-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "run_id"
  range_key    = "account_id"

  attribute {
    name = "run_id"
    type = "S"
  }

  attribute {
    name = "account_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "${local.prefix}-deploy-run-state", Purpose = "deploy-run-state" }
}

# ── Account Inventory — DynamoDB table for SFN pipeline + drift sweep ────────
# PK=account_id (S).
# GSI1: environment-index  → query all accounts in an environment
# GSI2: ou-index           → query all accounts in an OU
# GSI3: status-index       → query accounts by provisioning status (ordered by time)
resource "aws_dynamodb_table" "account_inventory" {
  count        = var.create_state_backend ? 1 : 0
  name         = "${local.prefix}-account-inventory"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "account_id"

  attribute {
    name = "account_id"
    type = "S"
  }

  attribute {
    name = "environment"
    type = "S"
  }

  attribute {
    name = "ou"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "last_deployed_at"
    type = "S"
  }

  global_secondary_index {
    name            = "environment-index"
    hash_key        = "environment"
    range_key       = "account_id"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "ou-index"
    hash_key        = "ou"
    range_key       = "account_id"
    projection_type = "ALL"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    range_key       = "last_deployed_at"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "${local.prefix}-account-inventory", Purpose = "account-inventory" }
}

# ── State Backend — Cross-Region Replication (DR) ────────────────────────────
# Replicates state objects to var.dr_region so the management account can
# recover all stack state if the primary region suffers an outage.
resource "aws_s3_bucket" "state_replica" {
  count    = var.create_state_backend && var.enable_state_replication ? 1 : 0
  provider = aws.dr
  bucket   = "${local.prefix}-terraform-state-replica"

  tags = { Name = "${local.prefix}-terraform-state-replica", Purpose = "dr-replica" }
}

resource "aws_s3_bucket_versioning" "state_replica" {
  count    = var.create_state_backend && var.enable_state_replication ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.state_replica[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_replica" {
  count    = var.create_state_backend && var.enable_state_replication ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.state_replica[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state_replica" {
  count    = var.create_state_backend && var.enable_state_replication ? 1 : 0
  provider = aws.dr
  bucket   = aws_s3_bucket.state_replica[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "replication_assume" {
  count = var.create_state_backend && var.enable_state_replication ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  count              = var.create_state_backend && var.enable_state_replication ? 1 : 0
  name               = "${local.prefix}-state-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume[0].json
}

data "aws_iam_policy_document" "replication" {
  count = var.create_state_backend && var.enable_state_replication ? 1 : 0

  statement {
    sid     = "SourceBucketRead"
    effect  = "Allow"
    actions = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.state[0].arn]
  }

  statement {
    sid    = "SourceObjectRead"
    effect = "Allow"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.state[0].arn}/*"]
  }

  statement {
    sid    = "DestinationObjectWrite"
    effect = "Allow"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = ["${aws_s3_bucket.state_replica[0].arn}/*"]
  }

  statement {
    sid       = "KmsDecryptSource"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["s3.${var.primary_region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "KmsEncryptDestination"
    effect    = "Allow"
    actions   = ["kms:Encrypt"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["s3.${var.dr_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "replication" {
  count  = var.create_state_backend && var.enable_state_replication ? 1 : 0
  name   = "${local.prefix}-state-replication"
  role   = aws_iam_role.replication[0].id
  policy = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "state" {
  count = var.create_state_backend && var.enable_state_replication ? 1 : 0

  # Replication requires versioning on the source bucket
  depends_on = [aws_s3_bucket_versioning.state]

  bucket = aws_s3_bucket.state[0].id
  role   = aws_iam_role.replication[0].arn

  rule {
    id     = "replicate-all-state"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.state_replica[0].arn
      storage_class = "STANDARD_IA"
    }
  }
}

# ── Current Account Info ─────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
data "aws_organizations_organization" "current" {}
