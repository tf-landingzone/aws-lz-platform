################################################################################
# 01-Organizations — Variables
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

# ── Organizations ────────────────────────────────────────────────────────────

variable "manage_organization" {
  description = "Whether to manage the AWS Organization itself."
  type        = bool
  default     = false
}

variable "feature_set" {
  type    = string
  default = "ALL"
}

variable "enabled_service_principals" {
  type = list(string)
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
  type    = list(string)
  default = ["SERVICE_CONTROL_POLICY", "TAG_POLICY", "BACKUP_POLICY"]
}

variable "organizational_units" {
  type = map(object({
    name       = string
    parent_key = optional(string, null)
    tags       = optional(map(string), {})
  }))
  default = {}
}

variable "accounts" {
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
  type    = map(list(string))
  default = {}
}

# ── Governance ───────────────────────────────────────────────────────────────

variable "service_control_policies" {
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
