################################################################################
# 06-Workload-Support — Main
################################################################################
# Customizations, IAM, ACM, Account Factory Trigger.
################################################################################

module "account_factory_trigger" {
  source = "../../modules/account-factory-trigger"
  count  = var.enable_account_factory_trigger ? 1 : 0

  create = true
  tags   = local.common_tags

  event_rule_name         = "${local.prefix}-account-created"
  github_repo             = var.github_repo
  github_workflow_id      = var.github_workflow_id
  github_ref              = var.github_ref
  github_token_secret_arn = var.github_token_secret_arn
  notification_emails     = var.account_creation_notification_emails
  skip_account_names      = var.skip_account_names
}

module "iam_resources" {
  source = "../../modules/iam-resources"
  count  = var.enable_iam_resources ? 1 : 0

  create = true
  tags   = local.common_tags

  users             = var.iam_users
  groups            = var.iam_groups
  roles             = var.iam_roles
  policies          = var.iam_policies
  saml_providers    = var.iam_saml_providers
  account_alias     = var.iam_account_alias
  instance_profiles = var.iam_instance_profiles
}

module "customizations" {
  source = "../../modules/customizations"
  count  = var.enable_customizations ? 1 : 0

  create = true
  tags   = local.common_tags

  cloudformation_stacks      = var.cloudformation_stacks
  cloudformation_stacksets   = var.cloudformation_stacksets
  service_catalog_portfolios = var.service_catalog_portfolios
  application_load_balancers = var.application_load_balancers
  network_load_balancers     = var.network_load_balancers
  launch_templates           = var.launch_templates
  autoscaling_groups         = var.autoscaling_groups
}

module "acm" {
  source = "../../modules/acm"
  count  = var.enable_acm ? 1 : 0

  create       = true
  tags         = local.common_tags
  certificates = var.acm_certificates
}
