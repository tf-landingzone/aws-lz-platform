################################################################################
# 04-Logging — Main
################################################################################
# Centralized logging and KMS keys.
# Independent state from security and networking.
################################################################################

module "centralized_logging" {
  source = "../../modules/centralized-logging"
  count  = var.enable_centralized_logging ? 1 : 0

  create = true
  tags   = local.common_tags

  central_log_bucket = var.central_log_bucket
  access_log_bucket  = var.log_access_log_bucket
  cloudwatch_to_s3   = var.cloudwatch_to_s3
  session_manager    = var.session_manager_logging
}

module "kms" {
  source = "../../modules/kms"
  count  = var.enable_kms ? 1 : 0

  create = true
  tags   = local.common_tags

  keys = var.kms_keys
}
