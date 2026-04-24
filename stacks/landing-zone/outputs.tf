################################################################################
# Landing Zone Orchestration - Outputs
################################################################################

# ── Organizations ────────────────────────────────────────────────────────────

output "organizational_units" {
  description = "All OUs created by the organizations module."
  value       = var.enable_organizations ? module.organizations[0].organizational_units : {}
}

output "ou_ids" {
  description = "Map of OU keys to OU IDs."
  value       = local.ou_ids
}

output "account_ids" {
  description = "Map of account keys to account IDs."
  value       = local.account_ids
}

# ── Governance ───────────────────────────────────────────────────────────────

output "service_control_policies" {
  description = "SCPs created by the governance module."
  value       = var.enable_governance ? module.governance[0].service_control_policies : {}
}

output "scp_ids" {
  description = "Map of SCP keys to policy IDs."
  value       = var.enable_governance ? module.governance[0].scp_ids : {}
}

# ── Identity Center ─────────────────────────────────────────────────────────

output "permission_sets" {
  description = "SSO permission sets created."
  value       = var.enable_identity_center ? module.identity_center[0].permission_sets : {}
}

output "permission_set_arns" {
  description = "Map of permission set keys to ARNs."
  value       = var.enable_identity_center ? module.identity_center[0].permission_set_arns : {}
}

output "group_ids" {
  description = "Resolved IdP group IDs."
  value       = var.enable_identity_center ? module.identity_center[0].group_ids : {}
}

# ── Security Baseline ───────────────────────────────────────────────────────

output "security_summary" {
  description = "Summary of org-level security services deployed."
  value       = var.enable_security_baseline ? module.security_baseline[0].security_summary : {}
}

# ── Budget Alerts ────────────────────────────────────────────────────────────

output "budgets" {
  description = "Budgets created."
  value       = var.enable_budget_alerts ? module.budget_alerts[0].budgets : {}
}

output "finops_summary" {
  description = "Summary of all FinOps resources."
  value       = var.enable_budget_alerts ? module.budget_alerts[0].finops_summary : {}
}

# ── Account Factory Trigger ───────────────────────────────────────────────────

output "account_factory_trigger" {
  description = "Account Factory EventBridge trigger details."
  value = var.enable_account_factory_trigger ? {
    event_rule_arn = module.account_factory_trigger[0].event_rule_arn
    sns_topic_arn  = module.account_factory_trigger[0].sns_topic_arn
    lambda_arn     = module.account_factory_trigger[0].lambda_function_arn
  } : null
}

# ── Networking ───────────────────────────────────────────────────────────────

output "networking" {
  description = "Networking module outputs (VPCs, TGW, etc.)."
  value       = var.enable_networking ? module.networking[0] : null
}

# ── Centralized Logging ─────────────────────────────────────────────────────

output "centralized_logging" {
  description = "Centralized logging module outputs."
  value = var.enable_centralized_logging ? {
    central_log_bucket_id    = module.centralized_logging[0].central_log_bucket_id
    central_log_bucket_arn   = module.centralized_logging[0].central_log_bucket_arn
    access_log_bucket_id     = module.centralized_logging[0].access_log_bucket_id
    access_log_bucket_arn    = module.centralized_logging[0].access_log_bucket_arn
    firehose_arn             = module.centralized_logging[0].firehose_delivery_stream_arn
    session_manager_document = module.centralized_logging[0].session_manager_document_name
  } : null
}

# ── Config Rules ─────────────────────────────────────────────────────────────

output "config_rules" {
  description = "Config Rules module outputs."
  value       = var.enable_config_rules ? module.config_rules[0] : null
}

# ── KMS ──────────────────────────────────────────────────────────────────────

output "kms" {
  description = "KMS module outputs."
  value       = var.enable_kms ? module.kms[0] : null
}

# ── Macie ────────────────────────────────────────────────────────────────────

output "macie" {
  description = "Macie module outputs."
  value       = var.enable_macie ? module.macie[0] : null
}

# ── Detective ────────────────────────────────────────────────────────────────

output "detective" {
  description = "Detective module outputs."
  value       = var.enable_detective ? module.detective[0] : null
}

# ── Audit Manager ────────────────────────────────────────────────────────────

output "audit_manager" {
  description = "Audit Manager module outputs."
  value       = var.enable_audit_manager ? module.audit_manager[0] : null
}

# ── IAM Resources ────────────────────────────────────────────────────────────

output "iam_resources" {
  description = "IAM Resources module outputs."
  value       = var.enable_iam_resources ? module.iam_resources[0] : null
}

# ── Customizations ───────────────────────────────────────────────────────────

output "customizations" {
  description = "Customizations module outputs."
  value       = var.enable_customizations ? module.customizations[0] : null
}

# ── Control Tower ────────────────────────────────────────────────────────────

output "control_tower" {
  description = "Control Tower module outputs."
  value       = var.enable_control_tower ? module.control_tower[0] : null
}

# ── SSM ──────────────────────────────────────────────────────────────────────

output "ssm" {
  description = "SSM module outputs."
  value       = var.enable_ssm ? module.ssm[0] : null
}

# ── Backup ───────────────────────────────────────────────────────────────────

output "backup" {
  description = "Backup module outputs."
  value       = var.enable_backup ? module.backup[0] : null
}

# ── Cost Reporting ───────────────────────────────────────────────────────────

output "cost_reporting" {
  description = "Cost Reporting module outputs."
  value       = var.enable_cost_reporting ? module.cost_reporting[0] : null
}

# ── Inspector ────────────────────────────────────────────────────────────────

output "inspector" {
  description = "Inspector module outputs."
  value       = var.enable_inspector ? module.inspector[0] : null
}

# ── ACM ──────────────────────────────────────────────────────────────────────

output "acm" {
  description = "ACM module outputs."
  value       = var.enable_acm ? module.acm[0] : null
}

# ── Combined Summary ─────────────────────────────────────────────────────────

output "landing_zone_summary" {
  description = "High-level summary of all deployed landing zone components."
  value = {
    organizations       = var.enable_organizations ? "enabled" : "disabled"
    governance          = var.enable_governance ? "enabled" : "disabled"
    identity_center     = var.enable_identity_center ? "enabled" : "disabled"
    security            = var.enable_security_baseline ? "enabled" : "disabled"
    budget_alerts       = var.enable_budget_alerts ? "enabled" : "disabled"
    account_factory     = var.enable_account_factory_trigger ? "enabled" : "disabled"
    networking          = var.enable_networking ? "enabled" : "disabled"
    centralized_logging = var.enable_centralized_logging ? "enabled" : "disabled"
    config_rules        = var.enable_config_rules ? "enabled" : "disabled"
    kms                 = var.enable_kms ? "enabled" : "disabled"
    macie               = var.enable_macie ? "enabled" : "disabled"
    detective           = var.enable_detective ? "enabled" : "disabled"
    audit_manager       = var.enable_audit_manager ? "enabled" : "disabled"
    iam_resources       = var.enable_iam_resources ? "enabled" : "disabled"
    customizations      = var.enable_customizations ? "enabled" : "disabled"
    control_tower       = var.enable_control_tower ? "enabled" : "disabled"
    ssm                 = var.enable_ssm ? "enabled" : "disabled"
    backup              = var.enable_backup ? "enabled" : "disabled"
    cost_reporting      = var.enable_cost_reporting ? "enabled" : "disabled"
    inspector           = var.enable_inspector ? "enabled" : "disabled"
    acm                 = var.enable_acm ? "enabled" : "disabled"
    ou_count            = var.enable_organizations ? length(module.organizations[0].ou_ids) : 0
    account_count       = var.enable_organizations ? length(module.organizations[0].account_ids) : 0
  }
}
