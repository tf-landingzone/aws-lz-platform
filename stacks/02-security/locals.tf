################################################################################
# 02-Security — Locals
################################################################################

locals {
  prefix = "${var.org}-${var.program}"

  common_tags = merge({
    Org        = var.org
    Program    = var.program
    Owner      = var.owner
    CostCenter = var.cost_center
    ManagedBy  = "terraform"
    Stack      = "02-security"
  }, var.extra_tags)

  # Cross-stack references from 01-organizations
  # Uncomment when using remote state backend:
  # ou_ids      = data.terraform_remote_state.organizations.outputs.ou_ids
  # account_ids = data.terraform_remote_state.organizations.outputs.account_ids
}

# ── Remote State: 01-organizations ───────────────────────────────────────────
# Uncomment when using remote state backend:
# data "terraform_remote_state" "organizations" {
#   backend = "s3"
#   config = {
#     bucket = "${var.org}-${var.program}-terraform-state"
#     key    = "01-organizations/terraform.tfstate"
#     region = var.primary_region
#   }
# }
