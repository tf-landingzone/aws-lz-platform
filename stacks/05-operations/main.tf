################################################################################
# 05-Operations — Main
################################################################################
# Budget alerts, SSM, Backup, Cost Reporting.
# Independent state from security and networking.
################################################################################

module "budget_alerts" {
  source = "../../modules/budget-alerts"
  count  = var.enable_budget_alerts ? 1 : 0

  create = true
  tags   = local.common_tags

  notification_topics   = var.notification_topics
  budgets               = var.budgets
  anomaly_monitors      = var.anomaly_monitors
  anomaly_subscriptions = var.anomaly_subscriptions
}

module "ssm" {
  source = "../../modules/ssm"
  count  = var.enable_ssm ? 1 : 0

  create = true
  tags   = local.common_tags

  parameters              = var.ssm_parameters
  documents               = var.ssm_documents
  associations            = var.ssm_associations
  maintenance_windows     = var.ssm_maintenance_windows
  patch_baselines         = var.ssm_patch_baselines
  default_patch_baselines = var.ssm_default_patch_baselines
}

module "backup" {
  source = "../../modules/backup"
  count  = var.enable_backup ? 1 : 0

  create = true
  tags   = local.common_tags

  vaults            = var.backup_vaults
  plans             = var.backup_plans
  org_backup_policy = var.backup_org_policy
  region_settings   = var.backup_region_settings
}

module "cost_reporting" {
  source = "../../modules/cost-reporting"
  count  = var.enable_cost_reporting ? 1 : 0

  create = true
  tags   = local.common_tags

  cost_usage_reports    = var.cost_usage_reports
  anomaly_monitors      = var.cost_anomaly_monitors
  anomaly_subscriptions = var.cost_anomaly_subscriptions
  budgets               = var.cost_budgets
}
