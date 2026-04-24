################################################################################
# 06-Workload-Support — Locals
################################################################################

locals {
  prefix = "${var.org}-${var.program}"

  common_tags = merge({
    Org        = var.org
    Program    = var.program
    Owner      = var.owner
    CostCenter = var.cost_center
    ManagedBy  = "terraform"
    Stack      = "06-workload-support"
  }, var.extra_tags)

  # Cross-stack references
  # Uncomment when using remote state backend:
  # networking = data.terraform_remote_state.networking.outputs
}

# ── Remote State: 03-networking ──────────────────────────────────────────────
# Uncomment when using remote state backend:
# data "terraform_remote_state" "networking" {
#   backend = "s3"
#   config = {
#     bucket = "${var.org}-${var.program}-terraform-state"
#     key    = "03-networking/terraform.tfstate"
#     region = var.primary_region
#   }
# }
