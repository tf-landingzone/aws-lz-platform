################################################################################
# 02-Security — Variables
################################################################################

# ── Global ───────────────────────────────────────────────────────────────────

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "org" {
  type = string
}

variable "program" {
  type    = string
  default = "lz"
}

variable "owner" {
  type    = string
  default = "platform-team"
}

variable "cost_center" {
  type    = string
  default = ""
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}

# ── Feature Flags ────────────────────────────────────────────────────────────

variable "enable_identity_center" {
  type    = bool
  default = false
}

variable "enable_security_baseline" {
  type    = bool
  default = false
}

variable "enable_config_rules" {
  type    = bool
  default = false
}

variable "enable_control_tower" {
  type    = bool
  default = false
}

variable "enable_inspector" {
  type    = bool
  default = false
}

variable "enable_macie" {
  type    = bool
  default = false
}

variable "enable_detective" {
  type    = bool
  default = false
}

variable "enable_audit_manager" {
  type    = bool
  default = false
}

# ── Identity Center ──────────────────────────────────────────────────────────

variable "group_lookups" {
  type = map(object({
    display_name = string
  }))
  default = {}
}

variable "permission_sets" {
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
  type = list(object({
    key    = string
    source = list(string)
  }))
  default = []
}

# ── Security Baseline ───────────────────────────────────────────────────────

variable "org_cloudtrail" {
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
  type    = bool
  default = false
}

variable "org_access_analyzer_name" {
  type    = string
  default = "org-access-analyzer"
}

# ── Config Rules ─────────────────────────────────────────────────────────────

variable "config_recorder" {
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
  type = map(object({
    template_body    = optional(string, null)
    template_file    = optional(string, null)
    template_s3_uri  = optional(string, null)
    input_parameters = optional(map(string), {})
  }))
  default = {}
}

variable "org_conformance_packs" {
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
  type = object({
    enabled          = optional(bool, false)
    name             = optional(string, "org-aggregator")
    use_organization = optional(bool, true)
    account_ids      = optional(list(string), [])
    regions          = optional(list(string), [])
  })
  default = {}
}

# ── Control Tower ────────────────────────────────────────────────────────────

variable "ct_controls" {
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

# ── Inspector ────────────────────────────────────────────────────────────────

variable "inspector_admin_account_id" {
  type    = string
  default = null
}

variable "inspector_account_ids" {
  type    = list(string)
  default = []
}

variable "inspector_resource_types" {
  type    = list(string)
  default = ["EC2", "ECR"]
}

variable "inspector_auto_enable" {
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
  type    = list(string)
  default = []
}

# ── Macie ────────────────────────────────────────────────────────────────────

variable "macie_admin_account_id" {
  type    = string
  default = null
}

variable "macie_finding_frequency" {
  type    = string
  default = "SIX_HOURS"
}

variable "macie_member_accounts" {
  type = map(object({
    account_id = string
    email      = string
    invite     = optional(bool, true)
    status     = optional(string, "ENABLED")
  }))
  default = {}
}

variable "macie_classification_jobs" {
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
  type = map(object({
    description            = optional(string, "")
    regex                  = optional(string, null)
    keywords               = optional(list(string), [])
    maximum_match_distance = optional(number, 50)
  }))
  default = {}
}

# ── Detective ────────────────────────────────────────────────────────────────

variable "detective_admin_account_id" {
  type    = string
  default = null
}

variable "detective_member_accounts" {
  type = map(object({
    account_id = string
    email      = string
  }))
  default = {}
}

# ── Audit Manager ────────────────────────────────────────────────────────────

variable "audit_manager_admin_account_id" {
  type    = string
  default = null
}

variable "audit_manager_kms_key_id" {
  type    = string
  default = null
}

variable "audit_manager_s3_bucket" {
  type    = string
  default = null
}

variable "audit_manager_s3_prefix" {
  type    = string
  default = "audit-manager"
}

variable "audit_manager_assessments" {
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
  type = map(object({
    description     = optional(string, "")
    compliance_type = optional(string, null)
    control_sets    = list(object({ name = string, controls = list(object({ id = string })) }))
  }))
  default = {}
}

variable "audit_manager_custom_controls" {
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
