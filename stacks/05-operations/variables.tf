################################################################################
# 05-Operations — Variables
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

variable "enable_budget_alerts" {
  type    = bool
  default = false
}

variable "enable_ssm" {
  type    = bool
  default = false
}

variable "enable_backup" {
  type    = bool
  default = false
}

variable "enable_cost_reporting" {
  type    = bool
  default = false
}

# ── Budget Alerts ────────────────────────────────────────────────────────────

variable "notification_topics" {
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
  type = map(object({
    name              = string
    monitor_type      = optional(string, "DIMENSIONAL")
    monitor_dimension = optional(string, "SERVICE")
    tags              = optional(map(string), {})
  }))
  default = {}
}

variable "anomaly_subscriptions" {
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

# ── SSM ──────────────────────────────────────────────────────────────────────

variable "ssm_parameters" {
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
  type    = map(string)
  default = {}
}

# ── Backup ───────────────────────────────────────────────────────────────────

variable "backup_vaults" {
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
  type    = any
  default = {}
}

variable "backup_org_policy" {
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
  type = object({
    enabled                             = optional(bool, false)
    resource_type_opt_in_preference     = optional(map(bool), {})
    resource_type_management_preference = optional(map(bool), {})
  })
  default = {}
}

# ── Cost Reporting ───────────────────────────────────────────────────────────

variable "cost_usage_reports" {
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
  type = map(object({
    monitor_type          = optional(string, "DIMENSIONAL")
    monitor_dimension     = optional(string, "SERVICE")
    monitor_specification = optional(string, null)
  }))
  default = {}
}

variable "cost_anomaly_subscriptions" {
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
