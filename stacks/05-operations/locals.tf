################################################################################
# 05-Operations — Locals
################################################################################

locals {
  prefix = "${var.org}-${var.program}"

  common_tags = merge({
    Org        = var.org
    Program    = var.program
    Owner      = var.owner
    CostCenter = var.cost_center
    ManagedBy  = "terraform"
    Stack      = "05-operations"
  }, var.extra_tags)
}
