################################################################################
# 04-Logging — Locals
################################################################################

locals {
  prefix = "${var.org}-${var.program}"

  common_tags = merge({
    Org        = var.org
    Program    = var.program
    Owner      = var.owner
    CostCenter = var.cost_center
    ManagedBy  = "terraform"
    Stack      = "04-logging"
  }, var.extra_tags)
}
