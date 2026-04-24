################################################################################
# 01-Organizations — Locals
################################################################################

locals {
  prefix = "${var.org}-${var.program}"

  common_tags = merge({
    Org        = var.org
    Program    = var.program
    Owner      = var.owner
    CostCenter = var.cost_center
    ManagedBy  = "terraform"
    Stack      = "01-organizations"
  }, var.extra_tags)
}
