################################################################################
# 02-Security — Main
################################################################################
# Identity, security baseline, compliance services.
# Independent state — changing security doesn't replan networking.
################################################################################

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ Identity Center — Permission Sets, Account Assignments, ABAC             ║
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
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ Security Baseline — CloudTrail, Config, GuardDuty, Security Hub          ║
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
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ Config Rules — Rules, Remediations, Conformance Packs                    ║
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
# ║ Control Tower — Controls/Guardrails                                       ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "control_tower" {
  source = "../../modules/control-tower"
  count  = var.enable_control_tower ? 1 : 0

  create = true
  tags   = local.common_tags

  controls       = var.ct_controls
  quarantine_scp = var.ct_quarantine_scp
  landing_zone   = var.ct_landing_zone
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ Inspector — Vulnerability Scanning                                        ║
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
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ Macie — Sensitive Data Discovery                                          ║
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
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ Detective — Security Investigation                                        ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

module "detective" {
  source = "../../modules/detective"
  count  = var.enable_detective ? 1 : 0

  create = true
  tags   = local.common_tags

  admin_account_id = var.detective_admin_account_id
  member_accounts  = var.detective_member_accounts
}

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║ Audit Manager — Compliance Assessments                                    ║
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
}
