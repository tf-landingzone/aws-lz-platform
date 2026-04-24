################################################################################
# Landing Zone Orchestration - Variables
################################################################################
# A single set of variables drives all 19 modules.
# All variables use map(object()) so they scale without code changes.
################################################################################

# ── Global ───────────────────────────────────────────────────────────────────

variable "primary_region" {
  description = "Primary AWS region for deployment."
  type        = string
  default     = "us-east-1"
}

variable "org" {
  description = "Organization short name used in naming conventions."
  type        = string
}

variable "program" {
  description = "Program or project name."
  type        = string
  default     = "lz"
}

variable "owner" {
  description = "Team or individual who owns these resources."
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "Cost center for billing."
  type        = string
  default     = ""
}

variable "extra_tags" {
  description = "Additional tags to merge into all resources."
  type        = map(string)
  default     = {}
}

# ── Feature Flags ────────────────────────────────────────────────────────────

variable "enable_organizations" {
  description = "Enable the Organizations module (OUs, accounts, delegated admins)."
  type        = bool
  default     = true
}

variable "enable_governance" {
  description = "Enable the Governance module (SCPs, tag policies, backup policies)."
  type        = bool
  default     = true
}

variable "enable_identity_center" {
  description = "Enable the Identity Center module (SSO permission sets, assignments)."
  type        = bool
  default     = true
}

variable "enable_security_baseline" {
  description = "Enable the org-level Security Baseline module."
  type        = bool
  default     = true
}

variable "enable_account_baselines" {
  description = "Enable per-account baselines (password policy, encryption, GuardDuty, etc.)."
  type        = bool
  default     = false
}

variable "enable_budget_alerts" {
  description = "Enable the Budget Alerts & FinOps module."
  type        = bool
  default     = true
}

# ── Organizations Module ─────────────────────────────────────────────────────

variable "manage_organization" {
  description = "Whether to manage the AWS Organization itself (set false if already exists)."
  type        = bool
  default     = false
}

variable "feature_set" {
  description = "Organization feature set: ALL or CONSOLIDATED_BILLING."
  type        = string
  default     = "ALL"
}

variable "enabled_service_principals" {
  description = "AWS service principals to enable at org level."
  type        = list(string)
  default = [
    "sso.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "cloudtrail.amazonaws.com",
    "access-analyzer.amazonaws.com",
    "tagpolicies.tag.amazonaws.com",
    "member.org.stacksets.cloudformation.amazonaws.com",
  ]
}

variable "enabled_policy_types" {
  description = "Organization policy types to enable."
  type        = list(string)
  default     = ["SERVICE_CONTROL_POLICY", "TAG_POLICY", "BACKUP_POLICY"]
}

variable "organizational_units" {
  description = "Map of OUs. Use parent_key for nesting under another OU."
  type = map(object({
    name       = string
    parent_key = optional(string, null)
    tags       = optional(map(string), {})
  }))
  default = {}
}

variable "accounts" {
  description = "Map of AWS accounts to create/import under OUs."
  type = map(object({
    name      = string
    email     = string
    ou_key    = optional(string, null)
    parent_id = optional(string, null)
    role_name = optional(string, "OrganizationAccountAccessRole")
    tags      = optional(map(string), {})
  }))
  default = {}
}

variable "delegated_administrators" {
  description = "Map of account IDs to lists of service principals for delegation."
  type        = map(list(string))
  default     = {}
}

# ── Governance Module ────────────────────────────────────────────────────────

variable "service_control_policies" {
  description = "Map of SCPs to create and attach."
  type = map(object({
    name            = string
    description     = optional(string, "")
    content         = optional(string, null)
    content_file    = optional(string, null)
    target_ids      = optional(list(string), [])
    target_ou_keys  = optional(list(string), [])
    target_root     = optional(bool, false)
    tags            = optional(map(string), {})
  }))
  default = {}
}

variable "tag_policies" {
  description = "Map of tag policies."
  type = map(object({
    name            = string
    description     = optional(string, "")
    content         = optional(string, null)
    content_file    = optional(string, null)
    target_ids      = optional(list(string), [])
    target_ou_keys  = optional(list(string), [])
    target_root     = optional(bool, false)
    tags            = optional(map(string), {})
  }))
  default = {}
}

variable "backup_policies" {
  description = "Map of backup policies."
  type = map(object({
    name            = string
    description     = optional(string, "")
    content         = optional(string, null)
    content_file    = optional(string, null)
    target_ids      = optional(list(string), [])
    target_ou_keys  = optional(list(string), [])
    target_root     = optional(bool, false)
    tags            = optional(map(string), {})
  }))
  default = {}
}

variable "ai_services_opt_out_policies" {
  description = "Map of AI services opt-out policies."
  type = map(object({
    name            = string
    description     = optional(string, "")
    content         = optional(string, null)
    content_file    = optional(string, null)
    target_ids      = optional(list(string), [])
    target_ou_keys  = optional(list(string), [])
    target_root     = optional(bool, false)
    tags            = optional(map(string), {})
  }))
  default = {}
}

# ── Identity Center Module ───────────────────────────────────────────────────

variable "group_lookups" {
  description = "Map of IdP group display names to look up (synced via SCIM)."
  type = map(object({
    display_name = string
  }))
  default = {}
}

variable "permission_sets" {
  description = "Map of SSO permission sets."
  type = map(object({
    name                 = string
    description          = optional(string, "")
    session_duration     = optional(string, "PT4H")
    relay_state          = optional(string, null)
    inline_policy        = optional(string, null)
    aws_managed_policies = optional(list(string), [])
    customer_managed_policies = optional(list(object({
      name = string
      path = optional(string, "/")
    })), [])
    permissions_boundary = optional(object({
      managed_policy_arn   = optional(string, null)
      customer_policy_name = optional(string, null)
      customer_policy_path = optional(string, "/")
    }), null)
    tags = optional(map(string), {})
  }))
  default = {}
}

variable "account_assignments" {
  description = "Map of account assignments linking principals to permission sets."
  type = map(object({
    permission_set_key = string
    principal_type     = optional(string, "GROUP")
    principal_name     = optional(string, null)
    principal_id       = optional(string, null)
    account_ids        = list(string)
  }))
  default = {}
}

variable "access_control_attributes" {
  description = "ABAC attributes for Identity Center."
  type = list(object({
    key    = string
    source = list(string)
  }))
  default = []
}

# ── Security Baseline (Org-level) ───────────────────────────────────────────

variable "org_cloudtrail" {
  description = "Org-level CloudTrail configuration."
  type = object({
    enabled                  = optional(bool, false)
    trail_name               = optional(string, "org-trail")
    s3_bucket_name           = optional(string, null)
    s3_key_prefix            = optional(string, "cloudtrail")
    kms_key_id               = optional(string, null)
    cloudwatch_log_group_arn = optional(string, null)
    cloudwatch_role_arn      = optional(string, null)
    event_selectors = optional(list(object({
      read_write_type           = optional(string, "All")
      include_management_events = optional(bool, true)
      data_resources = optional(list(object({
        type   = string
        values = list(string)
      })), [])
    })), [])
  })
  default = {}
}

variable "config_aggregator" {
  description = "Org-level Config aggregator configuration."
  type = object({
    enabled         = optional(bool, false)
    aggregator_name = optional(string, "org-aggregator")
    role_arn        = optional(string, null)
    all_regions     = optional(bool, true)
    regions         = optional(list(string), [])
  })
  default = {}
}

variable "guardduty_org" {
  description = "Org-level GuardDuty configuration."
  type = object({
    enabled                      = optional(bool, false)
    finding_publishing_frequency = optional(string, "FIFTEEN_MINUTES")
    auto_enable_members          = optional(bool, true)
    auto_enable_s3               = optional(bool, true)
    auto_enable_kubernetes       = optional(bool, true)
    auto_enable_malware          = optional(bool, false)
    member_accounts = optional(list(object({
      account_id = string
      email      = string
      invite     = optional(bool, true)
    })), [])
  })
  default = {}
}

variable "securityhub_org" {
  description = "Org-level Security Hub configuration."
  type = object({
    enabled                   = optional(bool, false)
    enable_default_standards  = optional(bool, true)
    control_finding_generator = optional(string, "SECURITY_CONTROL")
    auto_enable_controls      = optional(bool, true)
    auto_enable_members       = optional(bool, true)
    auto_enable_standards     = optional(string, "DEFAULT")
    standards = optional(list(string), [
      "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.0",
      "arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0",
    ])
  })
  default = {}
}

variable "enable_org_access_analyzer" {
  description = "Enable Organization-level IAM Access Analyzer."
  type        = bool
  default     = false
}

variable "org_access_analyzer_name" {
  description = "Name for the Organization-level Access Analyzer."
  type        = string
  default     = "org-access-analyzer"
}

# ── Budget Alerts ────────────────────────────────────────────────────────────

variable "notification_topics" {
  description = "Map of SNS notification topics for budgets/anomaly alerts."
  type = map(object({
    name              = string
    display_name      = optional(string, "")
    kms_key_id        = optional(string, null)
    email_subscribers = optional(list(string), [])
    tags              = optional(map(string), {})
  }))
  default = {}
}

variable "budgets" {
  description = "Map of AWS Budgets."
  type = map(object({
    name              = string
    budget_type       = optional(string, "COST")
    limit_amount      = string
    limit_unit        = optional(string, "USD")
    time_unit         = optional(string, "MONTHLY")
    time_period_start = optional(string, null)
    time_period_end   = optional(string, null)
    cost_filters = optional(list(object({
      name   = string
      values = list(string)
    })), [])
    cost_types = optional(object({
      include_credit             = optional(bool, false)
      include_discount           = optional(bool, true)
      include_other_subscription = optional(bool, true)
      include_recurring          = optional(bool, true)
      include_refund             = optional(bool, false)
      include_subscription       = optional(bool, true)
      include_support            = optional(bool, true)
      include_tax                = optional(bool, true)
      include_upfront            = optional(bool, true)
      use_amortized              = optional(bool, false)
      use_blended                = optional(bool, false)
    }), {})
    notifications = optional(list(object({
      comparison_operator       = optional(string, "GREATER_THAN")
      notification_type         = optional(string, "ACTUAL")
      threshold                 = number
      threshold_type            = optional(string, "PERCENTAGE")
      subscriber_emails         = optional(list(string), [])
      subscriber_sns_topic_keys = optional(list(string), [])
    })), [])
    tags = optional(map(string), {})
  }))
  default = {}
}

variable "anomaly_monitors" {
  description = "Map of Cost Explorer anomaly monitors."
  type = map(object({
    name              = string
    monitor_type      = optional(string, "DIMENSIONAL")
    monitor_dimension = optional(string, "SERVICE")
    tags              = optional(map(string), {})
  }))
  default = {}
}

variable "anomaly_subscriptions" {
  description = "Map of anomaly subscriptions (link monitors to notification targets)."
  type = map(object({
    name             = string
    frequency        = optional(string, "DAILY")
    threshold_amount = optional(number, 100)
    monitor_keys     = list(string)
    subscribers = list(object({
      type    = string
      address = string
    }))
    tags = optional(map(string), {})
  }))
  default = {}
}

# ── Account Factory Trigger ──────────────────────────────────────────────────

variable "enable_account_factory_trigger" {
  description = "Enable EventBridge → Lambda → GitHub Actions trigger for new account creation."
  type        = bool
  default     = false
}

variable "github_repo" {
  description = "GitHub repo in owner/repo format for workflow_dispatch."
  type        = string
  default     = ""
}

variable "github_workflow_id" {
  description = "GitHub Actions workflow filename to trigger on new account."
  type        = string
  default     = "account-setup.yml"
}

variable "github_ref" {
  description = "Git ref to trigger the workflow on."
  type        = string
  default     = "main"
}

variable "github_token_secret_arn" {
  description = "ARN of Secrets Manager secret containing GitHub PAT."
  type        = string
  default     = null
}

variable "account_creation_notification_emails" {
  description = "Email addresses to notify when a new account is created."
  type        = list(string)
  default     = []
}

variable "skip_account_names" {
  description = "Account names to skip in account factory trigger (foundational accounts)."
  type        = list(string)
  default     = ["log-archive", "audit", "shared-services"]
}

# ══════════════════════════════════════════════════════════════════════════════
# NEW MODULE FEATURE FLAGS
# ══════════════════════════════════════════════════════════════════════════════

variable "enable_networking" {
  description = "Enable the Networking module (VPCs, TGW, VPN, DX, Firewall, DNS)."
  type        = bool
  default     = false
}

variable "enable_centralized_logging" {
  description = "Enable the Centralized Logging module (S3, Firehose, Session Manager)."
  type        = bool
  default     = false
}

variable "enable_config_rules" {
  description = "Enable the Config Rules module (rules, remediations, conformance packs)."
  type        = bool
  default     = false
}

variable "enable_kms" {
  description = "Enable the KMS module (customer-managed encryption keys)."
  type        = bool
  default     = false
}

variable "enable_macie" {
  description = "Enable the Macie module (sensitive data discovery)."
  type        = bool
  default     = false
}

variable "enable_detective" {
  description = "Enable the Detective module (security investigation)."
  type        = bool
  default     = false
}

variable "enable_audit_manager" {
  description = "Enable the Audit Manager module (compliance assessments)."
  type        = bool
  default     = false
}

variable "enable_iam_resources" {
  description = "Enable the IAM Resources module (users, groups, roles, SAML)."
  type        = bool
  default     = false
}

variable "enable_customizations" {
  description = "Enable the Customizations module (CloudFormation, Service Catalog, ALB/NLB, ASG)."
  type        = bool
  default     = false
}

variable "enable_control_tower" {
  description = "Enable the Control Tower module (controls/guardrails, quarantine SCP)."
  type        = bool
  default     = false
}

variable "enable_ssm" {
  description = "Enable the SSM module (Parameter Store, Documents, Patch Baselines)."
  type        = bool
  default     = false
}

variable "enable_backup" {
  description = "Enable the Backup module (vaults, plans, selections)."
  type        = bool
  default     = false
}

variable "enable_cost_reporting" {
  description = "Enable the Cost Reporting module (CUR, anomaly detection, budgets)."
  type        = bool
  default     = false
}

variable "enable_inspector" {
  description = "Enable the Inspector module (vulnerability scanning)."
  type        = bool
  default     = false
}

variable "enable_acm" {
  description = "Enable the ACM module (certificate provisioning)."
  type        = bool
  default     = false
}

# ══════════════════════════════════════════════════════════════════════════════
# NETWORKING MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "net_delete_default_vpcs" {
  description = "Delete default VPCs in all regions."
  type        = bool
  default     = false
}

variable "net_ipam" {
  description = "IPAM configuration."
  type = object({
    enabled     = optional(bool, false)
    description = optional(string, "Organization IPAM")
    scopes      = optional(map(object({ description = optional(string, "") })), {})
    pools = optional(map(object({
      cidr        = string
      description = optional(string, "")
      scope_key   = optional(string, null)
      locale      = optional(string, null)
    })), {})
  })
  default = {}
}

variable "net_dhcp_options_sets" {
  description = "DHCP options sets."
  type        = any
  default     = {}
}

variable "net_prefix_lists" {
  description = "Managed prefix lists."
  type        = any
  default     = {}
}

variable "net_vpcs" {
  description = "VPC configurations."
  type        = any
  default     = {}
}

variable "net_vpc_peering" {
  description = "VPC peering connections."
  type        = any
  default     = {}
}

variable "net_transit_gateways" {
  description = "Transit gateway configurations."
  type        = any
  default     = {}
}

variable "net_transit_gateway_peering" {
  description = "Transit gateway peering attachments."
  type        = any
  default     = {}
}

variable "net_customer_gateways" {
  description = "Customer gateways for VPN."
  type        = any
  default     = {}
}

variable "net_vpn_connections" {
  description = "Site-to-site VPN connections."
  type        = any
  default     = {}
}

variable "net_dx_gateways" {
  description = "Direct Connect gateways."
  type        = any
  default     = {}
}

variable "net_network_firewalls" {
  description = "Network Firewall configurations."
  type        = any
  default     = {}
}

variable "net_gateway_load_balancers" {
  description = "Gateway Load Balancer configurations."
  type        = any
  default     = {}
}

variable "net_route53_resolver" {
  description = "Route53 Resolver configuration."
  type        = any
  default     = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# CENTRALIZED LOGGING MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "central_log_bucket" {
  description = "Central log bucket configuration."
  type = object({
    enabled             = optional(bool, true)
    bucket_name         = string
    kms_key_arn         = optional(string, null)
    versioning          = optional(bool, true)
    force_destroy       = optional(bool, false)
    lifecycle_rules     = optional(list(any), [])
    allowed_account_ids = optional(list(string), [])
  })
  default = {
    bucket_name = "central-logs"
  }
}

variable "log_access_log_bucket" {
  description = "S3 access log bucket configuration."
  type = object({
    enabled         = optional(bool, true)
    bucket_name     = string
    lifecycle_rules = optional(list(any), [])
  })
  default = {
    bucket_name = "central-access-logs"
  }
}

variable "cloudwatch_to_s3" {
  description = "CloudWatch-to-S3 via Kinesis Firehose config."
  type = object({
    enabled              = optional(bool, false)
    firehose_name        = optional(string, "cloudwatch-to-s3")
    s3_prefix            = optional(string, "cloudwatch/")
    buffering_size_mb    = optional(number, 5)
    buffering_interval_s = optional(number, 300)
  })
  default = {}
}

variable "session_manager_logging" {
  description = "Session Manager logging configuration."
  type = object({
    enabled              = optional(bool, false)
    s3_bucket_name       = optional(string, null)
    s3_key_prefix        = optional(string, "session-logs/")
    cloudwatch_log_group = optional(string, null)
    kms_key_id           = optional(string, null)
    run_as_enabled       = optional(bool, false)
    idle_session_timeout = optional(number, 20)
  })
  default = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# CONFIG RULES MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "config_recorder" {
  description = "AWS Config recorder settings."
  type = object({
    enabled             = optional(bool, false)
    name                = optional(string, "default")
    role_arn            = optional(string, null)
    recording_group_all = optional(bool, true)
    resource_types      = optional(list(string), [])
    include_global      = optional(bool, true)
    recording_frequency = optional(string, "CONTINUOUS")
    s3_bucket_name      = optional(string, null)
    s3_key_prefix       = optional(string, "config")
    sns_topic_arn       = optional(string, null)
    delivery_frequency  = optional(string, "Six_Hours")
  })
  default = {}
}

variable "lz_config_rules" {
  description = "Map of AWS Config rules."
  type = map(object({
    description            = optional(string, "")
    source_owner           = optional(string, "AWS")
    source_identifier      = string
    input_parameters       = optional(string, null)
    maximum_frequency      = optional(string, null)
    scope_compliance_types = optional(list(string), [])
    scope_tag_key          = optional(string, null)
    scope_tag_value        = optional(string, null)
  }))
  default = {}
}

variable "config_remediations" {
  description = "Map of auto-remediation configurations."
  type = map(object({
    config_rule_name = string
    target_type      = optional(string, "SSM_DOCUMENT")
    target_id        = string
    target_version   = optional(string, null)
    automatic        = optional(bool, false)
    max_attempts     = optional(number, 5)
    retry_seconds    = optional(number, 60)
    parameters = optional(map(object({
      static_values  = optional(list(string), [])
      resource_value = optional(string, null)
    })), {})
  }))
  default = {}
}

variable "org_config_rules" {
  description = "Map of organization-wide Config rules."
  type = map(object({
    description          = optional(string, "")
    source_identifier    = string
    input_parameters     = optional(string, null)
    maximum_frequency    = optional(string, null)
    resource_types_scope = optional(list(string), [])
    excluded_accounts    = optional(list(string), [])
  }))
  default = {}
}

variable "conformance_packs" {
  description = "Map of conformance packs."
  type = map(object({
    template_body    = optional(string, null)
    template_file    = optional(string, null)
    template_s3_uri  = optional(string, null)
    input_parameters = optional(map(string), {})
  }))
  default = {}
}

variable "org_conformance_packs" {
  description = "Map of organization-wide conformance packs."
  type = map(object({
    template_body     = optional(string, null)
    template_file     = optional(string, null)
    template_s3_uri   = optional(string, null)
    input_parameters  = optional(map(string), {})
    excluded_accounts = optional(list(string), [])
  }))
  default = {}
}

variable "lz_config_aggregator" {
  description = "Config aggregator for the config-rules module."
  type = object({
    enabled          = optional(bool, false)
    name             = optional(string, "org-aggregator")
    use_organization = optional(bool, true)
    account_ids      = optional(list(string), [])
    regions          = optional(list(string), [])
  })
  default = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# KMS MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "kms_keys" {
  description = "Map of KMS customer-managed keys."
  type = map(object({
    description             = optional(string, "")
    key_usage               = optional(string, "ENCRYPT_DECRYPT")
    key_spec                = optional(string, "SYMMETRIC_DEFAULT")
    enabled                 = optional(bool, true)
    enable_key_rotation     = optional(bool, true)
    rotation_period_in_days = optional(number, 365)
    deletion_window_in_days = optional(number, 30)
    multi_region            = optional(bool, false)
    policy                  = optional(string, null)
    aliases                 = optional(list(string), [])
    grants = optional(map(object({
      grantee_principal  = string
      operations         = list(string)
      retiring_principal = optional(string, null)
    })), {})
  }))
  default = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# MACIE MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "macie_admin_account_id" {
  description = "Macie delegated administrator account ID."
  type        = string
  default     = null
}

variable "macie_finding_frequency" {
  description = "Macie finding publishing frequency."
  type        = string
  default     = "SIX_HOURS"
}

variable "macie_member_accounts" {
  description = "Map of Macie member accounts."
  type = map(object({
    account_id = string
    email      = string
    invite     = optional(bool, true)
    status     = optional(string, "ENABLED")
  }))
  default = {}
}

variable "macie_classification_jobs" {
  description = "Map of Macie classification jobs."
  type = map(object({
    job_type        = optional(string, "SCHEDULED")
    s3_bucket_names = list(string)
    schedule_frequency = optional(object({
      daily_schedule   = optional(bool, false)
      weekly_schedule  = optional(string, null)
      monthly_schedule = optional(number, null)
    }), null)
    sampling_percentage        = optional(number, 100)
    custom_data_identifier_ids = optional(list(string), [])
    initial_run                = optional(bool, true)
  }))
  default = {}
}

variable "macie_custom_data_identifiers" {
  description = "Map of Macie custom data identifiers."
  type = map(object({
    description            = optional(string, "")
    regex                  = optional(string, null)
    keywords               = optional(list(string), [])
    maximum_match_distance = optional(number, 50)
  }))
  default = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# DETECTIVE MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "detective_admin_account_id" {
  description = "Detective delegated administrator account ID."
  type        = string
  default     = null
}

variable "detective_member_accounts" {
  description = "Map of Detective member accounts."
  type = map(object({
    account_id = string
    email      = string
  }))
  default = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# AUDIT MANAGER MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "audit_manager_admin_account_id" {
  description = "Audit Manager delegated admin account ID."
  type        = string
  default     = null
}

variable "audit_manager_kms_key_id" {
  description = "KMS key for Audit Manager encryption."
  type        = string
  default     = null
}

variable "audit_manager_s3_bucket" {
  description = "Default S3 bucket for assessment reports."
  type        = string
  default     = null
}

variable "audit_manager_s3_prefix" {
  description = "Default S3 prefix for assessment reports."
  type        = string
  default     = "audit-manager"
}

variable "audit_manager_assessments" {
  description = "Map of Audit Manager assessments."
  type = map(object({
    framework_id   = string
    roles          = list(object({ role_arn = string, role_type = optional(string, "PROCESS_OWNER") }))
    scope_accounts = optional(list(string), [])
    scope_services = optional(list(string), [])
    s3_bucket      = optional(string, null)
    s3_prefix      = optional(string, null)
    description    = optional(string, "")
  }))
  default = {}
}

variable "audit_manager_custom_frameworks" {
  description = "Map of custom compliance frameworks."
  type = map(object({
    description     = optional(string, "")
    compliance_type = optional(string, null)
    control_sets    = list(object({ name = string, controls = list(object({ id = string })) }))
  }))
  default = {}
}

variable "audit_manager_custom_controls" {
  description = "Map of custom controls."
  type = map(object({
    description              = optional(string, "")
    testing_information      = optional(string, "")
    action_plan_title        = optional(string, "")
    action_plan_instructions = optional(string, "")
    data_sources = optional(list(object({
      source_name          = string
      source_type          = optional(string, "AWS_Config")
      source_keyword_type  = optional(string, "CONFIG_RULE")
      source_keyword_value = optional(string, null)
      troubleshooting_text = optional(string, "")
    })), [])
  }))
  default = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# IAM RESOURCES MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "iam_users" {
  description = "Map of IAM users."
  type = map(object({
    path                 = optional(string, "/")
    permissions_boundary = optional(string, null)
    force_destroy        = optional(bool, false)
    groups               = optional(list(string), [])
    policies             = optional(list(string), [])
    inline_policies      = optional(map(string), {})
  }))
  default = {}
}

variable "iam_groups" {
  description = "Map of IAM groups."
  type = map(object({
    path            = optional(string, "/")
    policies        = optional(list(string), [])
    inline_policies = optional(map(string), {})
  }))
  default = {}
}

variable "iam_roles" {
  description = "Map of IAM roles."
  type = map(object({
    path                 = optional(string, "/")
    description          = optional(string, "")
    assume_role_policy   = string
    max_session_duration = optional(number, 3600)
    permissions_boundary = optional(string, null)
    policies             = optional(list(string), [])
    inline_policies      = optional(map(string), {})
  }))
  default = {}
}

variable "iam_policies" {
  description = "Map of IAM managed policies."
  type = map(object({
    path        = optional(string, "/")
    description = optional(string, "")
    policy      = string
  }))
  default = {}
}

variable "iam_saml_providers" {
  description = "Map of SAML identity providers."
  type = map(object({
    saml_metadata_document = string
  }))
  default = {}
}

variable "iam_account_alias" {
  description = "IAM account alias."
  type        = string
  default     = null
}

variable "iam_instance_profiles" {
  description = "Map of IAM instance profiles."
  type = map(object({
    role_name = string
    path      = optional(string, "/")
  }))
  default = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# CUSTOMIZATIONS MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "cloudformation_stacks" {
  description = "Map of CloudFormation stacks."
  type = map(object({
    template_body = optional(string, null)
    template_url  = optional(string, null)
    parameters    = optional(map(string), {})
    capabilities  = optional(list(string), ["CAPABILITY_NAMED_IAM"])
    on_failure    = optional(string, "ROLLBACK")
    timeout       = optional(number, 30)
    iam_role_arn  = optional(string, null)
  }))
  default = {}
}

variable "cloudformation_stacksets" {
  description = "Map of CloudFormation StackSets."
  type = map(object({
    template_body                = optional(string, null)
    template_url                 = optional(string, null)
    parameters                   = optional(map(string), {})
    capabilities                 = optional(list(string), ["CAPABILITY_NAMED_IAM"])
    permission_model             = optional(string, "SERVICE_MANAGED")
    auto_deployment_enabled      = optional(bool, true)
    auto_deployment_retain       = optional(bool, false)
    call_as                      = optional(string, "DELEGATED_ADMIN")
    target_ou_ids                = optional(list(string), [])
    target_account_ids           = optional(list(string), [])
    target_regions               = optional(list(string), [])
    max_concurrent_count         = optional(number, null)
    max_concurrent_percentage    = optional(number, 100)
    failure_tolerance_count      = optional(number, null)
    failure_tolerance_percentage = optional(number, 10)
    administration_role_arn      = optional(string, null)
    execution_role_name          = optional(string, null)
  }))
  default = {}
}

variable "service_catalog_portfolios" {
  description = "Map of Service Catalog portfolios."
  type = map(object({
    description    = optional(string, "")
    provider_name  = string
    products       = optional(any, {})
    principal_arns = optional(list(string), [])
    share_accounts = optional(list(string), [])
    share_org_node = optional(string, null)
  }))
  default = {}
}

variable "application_load_balancers" {
  description = "Map of Application Load Balancers."
  type        = any
  default     = {}
}

variable "network_load_balancers" {
  description = "Map of Network Load Balancers."
  type        = any
  default     = {}
}

variable "launch_templates" {
  description = "Map of EC2 launch templates."
  type        = any
  default     = {}
}

variable "autoscaling_groups" {
  description = "Map of Auto Scaling groups."
  type        = any
  default     = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# CONTROL TOWER MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "ct_controls" {
  description = "Map of Control Tower controls (guardrails) to enable."
  type = map(object({
    control_identifier = string
    target_ou_arn      = string
    parameters = optional(list(object({
      key   = string
      value = string
    })), [])
  }))
  default = {}
}

variable "ct_quarantine_scp" {
  description = "Quarantine SCP for newly-created accounts."
  type = object({
    enabled     = optional(bool, false)
    name        = optional(string, "QuarantinePolicy")
    description = optional(string, "Deny all actions for quarantined accounts")
    policy      = optional(string, null)
    target_ids  = optional(list(string), [])
  })
  default = {}
}

variable "ct_landing_zone" {
  description = "Control Tower Landing Zone configuration."
  type = object({
    enabled                = optional(bool, false)
    governed_regions       = optional(list(string), [])
    logging_account_id     = optional(string, null)
    security_account_id    = optional(string, null)
    kms_key_arn            = optional(string, null)
    access_logging_enabled = optional(bool, true)
  })
  default = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# SSM MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "ssm_parameters" {
  description = "Map of SSM parameters."
  type = map(object({
    type            = optional(string, "String")
    value           = optional(string, null)
    description     = optional(string, "")
    tier            = optional(string, "Standard")
    key_id          = optional(string, null)
    allowed_pattern = optional(string, null)
    data_type       = optional(string, "text")
  }))
  default = {}
}

variable "ssm_documents" {
  description = "Map of SSM documents."
  type = map(object({
    document_type   = optional(string, "Automation")
    document_format = optional(string, "YAML")
    content         = string
    target_type     = optional(string, null)
    version_name    = optional(string, null)
  }))
  default = {}
}

variable "ssm_associations" {
  description = "Map of SSM associations."
  type = map(object({
    document_name       = string
    schedule_expression = optional(string, null)
    compliance_severity = optional(string, "MEDIUM")
    max_concurrency     = optional(string, "10")
    max_errors          = optional(string, "10")
    parameters          = optional(map(list(string)), {})
    targets = optional(list(object({
      key    = string
      values = list(string)
    })), [])
  }))
  default = {}
}

variable "ssm_maintenance_windows" {
  description = "Map of SSM maintenance windows."
  type = map(object({
    schedule                   = string
    duration                   = number
    cutoff                     = number
    allow_unassociated_targets = optional(bool, true)
    enabled                    = optional(bool, true)
    schedule_timezone          = optional(string, "UTC")
  }))
  default = {}
}

variable "ssm_patch_baselines" {
  description = "Map of SSM patch baselines."
  type = map(object({
    operating_system = optional(string, "AMAZON_LINUX_2")
    approved_patches = optional(list(string), [])
    rejected_patches = optional(list(string), [])
    approval_rules = optional(list(object({
      approve_after_days  = optional(number, 7)
      compliance_level    = optional(string, "CRITICAL")
      enable_non_security = optional(bool, false)
      patch_filters = list(object({
        key    = string
        values = list(string)
      }))
    })), [])
  }))
  default = {}
}

variable "ssm_default_patch_baselines" {
  description = "Map of operating system to patch baseline key."
  type        = map(string)
  default     = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# BACKUP MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "backup_vaults" {
  description = "Map of AWS Backup vaults."
  type = map(object({
    kms_key_arn         = optional(string, null)
    force_destroy       = optional(bool, false)
    lock_min_retention  = optional(number, null)
    lock_max_retention  = optional(number, null)
    lock_changeable_for = optional(number, null)
    access_policy       = optional(string, null)
    notifications = optional(object({
      sns_topic_arn = string
      events        = list(string)
    }), null)
  }))
  default = {}
}

variable "backup_plans" {
  description = "Map of AWS Backup plans."
  type        = any
  default     = {}
}

variable "backup_org_policy" {
  description = "Organization backup policy."
  type = object({
    enabled     = optional(bool, false)
    name        = optional(string, "org-backup-policy")
    description = optional(string, "Organization-wide backup policy")
    content     = optional(string, null)
    target_ids  = optional(list(string), [])
  })
  default = {}
}

variable "backup_region_settings" {
  description = "AWS Backup region settings."
  type = object({
    enabled                             = optional(bool, false)
    resource_type_opt_in_preference     = optional(map(bool), {})
    resource_type_management_preference = optional(map(bool), {})
  })
  default = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# COST REPORTING MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "cost_usage_reports" {
  description = "Map of AWS Cost and Usage Reports."
  type = map(object({
    time_unit                  = optional(string, "DAILY")
    format                     = optional(string, "Parquet")
    compression                = optional(string, "Parquet")
    s3_bucket                  = string
    s3_prefix                  = optional(string, "cur")
    s3_region                  = optional(string, null)
    additional_schema_elements = optional(list(string), ["RESOURCES"])
    additional_artifacts       = optional(list(string), ["ATHENA"])
    refresh_closed_reports     = optional(bool, true)
    report_versioning          = optional(string, "OVERWRITE_REPORT")
  }))
  default = {}
}

variable "cost_anomaly_monitors" {
  description = "Map of cost anomaly monitors."
  type = map(object({
    monitor_type          = optional(string, "DIMENSIONAL")
    monitor_dimension     = optional(string, "SERVICE")
    monitor_specification = optional(string, null)
  }))
  default = {}
}

variable "cost_anomaly_subscriptions" {
  description = "Map of cost anomaly subscriptions."
  type = map(object({
    frequency      = optional(string, "DAILY")
    monitor_keys   = list(string)
    threshold      = optional(number, 100)
    threshold_type = optional(string, "PERCENTAGE")
    subscribers = list(object({
      type    = string
      address = string
    }))
  }))
  default = {}
}

variable "cost_budgets" {
  description = "Map of organization-level budgets."
  type = map(object({
    budget_type       = optional(string, "COST")
    limit_amount      = string
    limit_unit        = optional(string, "USD")
    time_unit         = optional(string, "MONTHLY")
    time_period_start = optional(string, null)
    time_period_end   = optional(string, null)
    cost_types = optional(object({
      include_tax          = optional(bool, true)
      include_subscription = optional(bool, true)
      include_support      = optional(bool, true)
      include_refund       = optional(bool, false)
      include_credit       = optional(bool, false)
      use_blended          = optional(bool, false)
    }), {})
    notifications = optional(list(object({
      comparison_operator        = optional(string, "GREATER_THAN")
      threshold                  = number
      threshold_type             = optional(string, "PERCENTAGE")
      notification_type          = optional(string, "ACTUAL")
      subscriber_email_addresses = optional(list(string), [])
      subscriber_sns_arns        = optional(list(string), [])
    })), [])
    cost_filter = optional(map(list(string)), {})
  }))
  default = {}
}

# ══════════════════════════════════════════════════════════════════════════════
# INSPECTOR MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "inspector_admin_account_id" {
  description = "Delegated admin account ID for Inspector."
  type        = string
  default     = null
}

variable "inspector_account_ids" {
  description = "Account IDs to enable Inspector scanning for."
  type        = list(string)
  default     = []
}

variable "inspector_resource_types" {
  description = "Resource types to scan. Valid: EC2, ECR, LAMBDA, LAMBDA_CODE, CODE_REPOSITORY."
  type        = list(string)
  default     = ["EC2", "ECR"]
}

variable "inspector_auto_enable" {
  description = "Auto-enable scanning for new org member accounts."
  type = object({
    ec2             = optional(bool, true)
    ecr             = optional(bool, true)
    lambda          = optional(bool, false)
    lambda_code     = optional(bool, false)
    code_repository = optional(bool, false)
  })
  default = null
}

variable "inspector_member_account_ids" {
  description = "Account IDs to associate as Inspector members."
  type        = list(string)
  default     = []
}

# ══════════════════════════════════════════════════════════════════════════════
# ACM MODULE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════

variable "acm_certificates" {
  description = "Map of ACM certificates to provision."
  type = map(object({
    domain_name               = string
    subject_alternative_names = optional(list(string), [])
    validation_method         = optional(string, "DNS")
    key_algorithm             = optional(string, null)
    certificate_authority_arn = optional(string, null)
    transparency_logging      = optional(string, null)
    zone_id                   = optional(string, null)
    wait_for_validation       = optional(bool, true)
    tags                      = optional(map(string), {})
  }))
  default = {}
}
