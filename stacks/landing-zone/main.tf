################################################################################
# Landing Zone Orchestration - Main
################################################################################
# Thin orchestration layer that calls all 19 dynamic modules.
# Each module is gated by a feature flag and receives variables pass-through.
# Zero logic here — all complexity lives in the modules.
################################################################################

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 1. ORGANIZATIONS — OUs, Accounts, Delegated Admins                      ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "organizations" {
  source = "../../modules/organizations"
  count  = var.enable_organizations ? 1 : 0

  create = true
  tags   = local.common_tags

  manage_organization        = var.manage_organization
  feature_set                = var.feature_set
  enabled_service_principals = var.enabled_service_principals
  enabled_policy_types       = var.enabled_policy_types
  organizational_units       = var.organizational_units
  accounts                   = var.accounts
  delegated_administrators   = var.delegated_administrators
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 2. GOVERNANCE — SCPs, Tag Policies, Backup Policies, AI Opt-Out         ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

# Resolve OU keys + "root" flag to actual target IDs. This lets config YAML
# reference OUs semantically (e.g. target_ou_keys = ["workloads_prod"]) without
# knowing the generated OU IDs.
locals {
  _ou_id_by_key = var.enable_organizations ? {
    for k, v in module.organizations[0].organizational_units : k => v.id
  } : {}
  _root_id = var.enable_organizations ? try(module.organizations[0].organization.root_id, null) : null

  _resolve_scp_targets = {
    for pk, p in var.service_control_policies : pk => distinct(concat(
      p.target_ids,
      [for k in p.target_ou_keys : local._ou_id_by_key[k] if contains(keys(local._ou_id_by_key), k)],
      p.target_root && local._root_id != null ? [local._root_id] : [],
    ))
  }
  _resolve_tag_targets = {
    for pk, p in var.tag_policies : pk => distinct(concat(
      p.target_ids,
      [for k in p.target_ou_keys : local._ou_id_by_key[k] if contains(keys(local._ou_id_by_key), k)],
      p.target_root && local._root_id != null ? [local._root_id] : [],
    ))
  }
  _resolve_backup_targets = {
    for pk, p in var.backup_policies : pk => distinct(concat(
      p.target_ids,
      [for k in p.target_ou_keys : local._ou_id_by_key[k] if contains(keys(local._ou_id_by_key), k)],
      p.target_root && local._root_id != null ? [local._root_id] : [],
    ))
  }
  _resolve_aiopt_targets = {
    for pk, p in var.ai_services_opt_out_policies : pk => distinct(concat(
      p.target_ids,
      [for k in p.target_ou_keys : local._ou_id_by_key[k] if contains(keys(local._ou_id_by_key), k)],
      p.target_root && local._root_id != null ? [local._root_id] : [],
    ))
  }

  service_control_policies_resolved = {
    for k, v in var.service_control_policies : k => {
      name         = v.name
      description  = v.description
      content      = v.content
      content_file = v.content_file
      target_ids   = local._resolve_scp_targets[k]
      tags         = v.tags
    }
  }
  tag_policies_resolved = {
    for k, v in var.tag_policies : k => {
      name         = v.name
      description  = v.description
      content      = v.content
      content_file = v.content_file
      target_ids   = local._resolve_tag_targets[k]
      tags         = v.tags
    }
  }
  backup_policies_resolved = {
    for k, v in var.backup_policies : k => {
      name         = v.name
      description  = v.description
      content      = v.content
      content_file = v.content_file
      target_ids   = local._resolve_backup_targets[k]
      tags         = v.tags
    }
  }
  ai_services_opt_out_policies_resolved = {
    for k, v in var.ai_services_opt_out_policies : k => {
      name         = v.name
      description  = v.description
      content      = v.content
      content_file = v.content_file
      target_ids   = local._resolve_aiopt_targets[k]
      tags         = v.tags
    }
  }
}

module "governance" {
  source = "../../modules/governance"
  count  = var.enable_governance ? 1 : 0

  create = true
  tags   = local.common_tags

  service_control_policies     = local.service_control_policies_resolved
  tag_policies                 = local.tag_policies_resolved
  backup_policies              = local.backup_policies_resolved
  ai_services_opt_out_policies = local.ai_services_opt_out_policies_resolved

  depends_on = [module.organizations]
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 3. IDENTITY CENTER — Permission Sets, Account Assignments, ABAC         ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "identity_center" {
  source = "../../modules/identity-center"
  count  = var.enable_identity_center ? 1 : 0

  create = true
  tags   = local.common_tags

  group_lookups             = var.group_lookups
  permission_sets           = var.permission_sets
  account_assignments       = var.account_assignments
  access_control_attributes = var.access_control_attributes

  depends_on = [module.organizations]
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 4. SECURITY BASELINE (Org-Level) — CloudTrail, Config, GuardDuty, etc.  ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "security_baseline" {
  source = "../../modules/security-baseline"
  count  = var.enable_security_baseline ? 1 : 0

  create = true
  tags   = local.common_tags

  org_cloudtrail             = var.org_cloudtrail
  config_aggregator          = var.config_aggregator
  guardduty_org              = var.guardduty_org
  securityhub_org            = var.securityhub_org
  enable_org_access_analyzer = var.enable_org_access_analyzer
  org_access_analyzer_name   = var.org_access_analyzer_name

  depends_on = [module.organizations]
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 5. BUDGET ALERTS — Budgets, Anomaly Detection, Notifications            ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

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

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 6. ACCOUNT FACTORY TRIGGER — EventBridge → Lambda → GitHub Actions        ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

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

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 7. NETWORKING — VPCs, TGW, VPN, DX, Firewall, DNS                       ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "networking" {
  source = "../../modules/networking"
  count  = var.enable_networking ? 1 : 0

  create = true
  tags   = local.common_tags

  delete_default_vpcs     = var.net_delete_default_vpcs
  ipam                    = var.net_ipam
  dhcp_options_sets       = var.net_dhcp_options_sets
  prefix_lists            = var.net_prefix_lists
  vpcs                    = var.net_vpcs
  vpc_peering             = var.net_vpc_peering
  transit_gateways        = var.net_transit_gateways
  transit_gateway_peering = var.net_transit_gateway_peering
  customer_gateways       = var.net_customer_gateways
  vpn_connections         = var.net_vpn_connections
  dx_gateways             = var.net_dx_gateways
  network_firewalls       = var.net_network_firewalls
  gateway_load_balancers  = var.net_gateway_load_balancers
  route53_resolver        = var.net_route53_resolver

  depends_on = [module.organizations]
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 8. CENTRALIZED LOGGING — Central S3, Firehose, Session Manager           ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

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

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 9. CONFIG RULES — AWS Config Rules, Remediations, Conformance Packs      ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "config_rules" {
  source = "../../modules/config-rules"
  count  = var.enable_config_rules ? 1 : 0

  create = true
  tags   = local.common_tags

  config_recorder       = var.config_recorder
  config_rules          = var.lz_config_rules
  config_remediations   = var.config_remediations
  org_config_rules      = var.org_config_rules
  conformance_packs     = var.conformance_packs
  org_conformance_packs = var.org_conformance_packs
  config_aggregator     = var.lz_config_aggregator

  depends_on = [module.security_baseline]
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 10. KMS — Customer-Managed Encryption Keys                               ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "kms" {
  source = "../../modules/kms"
  count  = var.enable_kms ? 1 : 0

  create = true
  tags   = local.common_tags

  keys = var.kms_keys
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 11. MACIE — Sensitive Data Discovery                                      ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "macie" {
  source = "../../modules/macie"
  count  = var.enable_macie ? 1 : 0

  create = true
  tags   = local.common_tags

  admin_account_id             = var.macie_admin_account_id
  finding_publishing_frequency = var.macie_finding_frequency
  member_accounts              = var.macie_member_accounts
  classification_jobs          = var.macie_classification_jobs
  custom_data_identifiers      = var.macie_custom_data_identifiers

  depends_on = [module.organizations]
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 12. DETECTIVE — Security Investigation                                    ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "detective" {
  source = "../../modules/detective"
  count  = var.enable_detective ? 1 : 0

  create = true
  tags   = local.common_tags

  admin_account_id = var.detective_admin_account_id
  member_accounts  = var.detective_member_accounts

  depends_on = [module.organizations]
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 13. AUDIT MANAGER — Compliance Assessments                                ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "audit_manager" {
  source = "../../modules/audit-manager"
  count  = var.enable_audit_manager ? 1 : 0

  create = true
  tags   = local.common_tags

  admin_account_id  = var.audit_manager_admin_account_id
  kms_key_id        = var.audit_manager_kms_key_id
  default_s3_bucket = var.audit_manager_s3_bucket
  default_s3_prefix = var.audit_manager_s3_prefix
  assessments       = var.audit_manager_assessments
  custom_frameworks = var.audit_manager_custom_frameworks
  custom_controls   = var.audit_manager_custom_controls

  depends_on = [module.organizations]
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 14. IAM RESOURCES — Users, Groups, Roles, SAML Providers                 ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

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

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 15. CUSTOMIZATIONS — CloudFormation, Service Catalog, ALB/NLB, EC2/ASG   ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

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

  depends_on = [module.networking]
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 16. CONTROL TOWER — Controls/Guardrails, Quarantine SCP                   ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "control_tower" {
  source = "../../modules/control-tower"
  count  = var.enable_control_tower ? 1 : 0

  create = true
  tags   = local.common_tags

  controls       = var.ct_controls
  quarantine_scp = var.ct_quarantine_scp
  landing_zone   = var.ct_landing_zone

  depends_on = [module.organizations]
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 17. SSM — Parameter Store, Documents, Patch Baselines                     ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

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

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 18. BACKUP — Vaults, Plans, Selections, Organization Policies            ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

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

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 19. COST REPORTING — CUR, Anomaly Detection, Organization Budgets        ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

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

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 20. INSPECTOR — Vulnerability Scanning (EC2, ECR, Lambda)                ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "inspector" {
  source = "../../modules/inspector"
  count  = var.enable_inspector ? 1 : 0

  create = true

  admin_account_id   = var.inspector_admin_account_id
  account_ids        = var.inspector_account_ids
  resource_types     = var.inspector_resource_types
  auto_enable        = var.inspector_auto_enable
  member_account_ids = var.inspector_member_account_ids

  depends_on = [module.organizations]
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ 21. ACM — Certificate Manager                                            ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "acm" {
  source = "../../modules/acm"
  count  = var.enable_acm ? 1 : 0

  create = true
  tags   = local.common_tags

  certificates = var.acm_certificates
}
