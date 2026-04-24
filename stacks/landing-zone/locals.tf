################################################################################
# Landing Zone Orchestration - Locals
################################################################################
# Cross-module wiring, naming conventions, and computed values
################################################################################

locals {
  prefix = "${var.org}-${var.program}"

  common_tags = merge({
    Org        = var.org
    Program    = var.program
    Owner      = var.owner
    CostCenter = var.cost_center
    ManagedBy  = "terraform"
  }, var.extra_tags)

  # ── Cross-module references ────────────────────────────────────────────────
  # OU IDs from organizations module → governance targets
  ou_ids = var.enable_organizations ? module.organizations[0].ou_ids : {}

  # Account IDs from organizations module → identity-center assignments
  account_ids = var.enable_organizations ? module.organizations[0].account_ids : {}
}
