################################################################################
# 04-Logging — Variables
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

variable "enable_centralized_logging" {
  type    = bool
  default = false
}

variable "enable_kms" {
  type    = bool
  default = false
}

# ── Centralized Logging ─────────────────────────────────────────────────────

variable "central_log_bucket" {
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

# ── KMS ──────────────────────────────────────────────────────────────────────

variable "kms_keys" {
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
