###############################################################################
# Account Setup — variables (passed by pipeline or tfvars)
###############################################################################

variable "account_id" {
  description = "Target AWS account ID (12 digits)"
  type        = string

  validation {
    condition     = can(regex("^\\d{12}$", var.account_id))
    error_message = "Account ID must be exactly 12 digits."
  }
}

variable "account_name" {
  description = "Target AWS account name (e.g. prod-app-001)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$", var.account_name))
    error_message = "Account name must be 3-50 chars, lowercase alphanumeric with hyphens, no leading/trailing hyphens."
  }
}

variable "environment" {
  description = "Account environment classification"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development", "sandbox"], var.environment)
    error_message = "Environment must be one of: production, staging, development, sandbox."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d$", var.aws_region))
    error_message = "Must be a valid AWS region (e.g. us-east-1, eu-west-1)."
  }
}

variable "assume_role_name" {
  description = "IAM role name to assume in the target account (created by Control Tower)"
  type        = string
  default     = "AWSControlTowerExecution"

  validation {
    condition     = can(regex("^[a-zA-Z_+=,.@-]{1,64}$", var.assume_role_name))
    error_message = "Role name must be 1-64 chars, valid IAM role name characters."
  }
}

variable "policies" {
  description = "Map of IAM policies to push to the target account (key → {name, file})"
  type = map(object({
    name = string
    file = string
  }))
  default = {}
}

variable "assignments" {
  description = "Map of SSO assignments: existing group → existing permission set → this account"
  type = map(object({
    permission_set_name = string
    sso_group_name      = string
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Security Baseline — environment-specific defaults resolved by Python script
# =============================================================================

variable "security_baseline" {
  description = "Security hardening configuration for the target account"
  type = object({
    enable_password_policy       = optional(bool, true)
    enable_ebs_encryption        = optional(bool, true)
    enable_s3_public_access_block = optional(bool, true)
    enable_access_analyzer       = optional(bool, true)
    password_policy = optional(object({
      minimum_length        = optional(number, 14)
      require_lowercase     = optional(bool, true)
      require_uppercase     = optional(bool, true)
      require_numbers       = optional(bool, true)
      require_symbols       = optional(bool, true)
      allow_users_to_change = optional(bool, true)
      max_age_days          = optional(number, 90)
      reuse_prevention      = optional(number, 24)
      hard_expiry           = optional(bool, false)
    }), {})
  })
  default = {}
}
