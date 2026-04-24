################################################################################
# 06-Workload-Support — Variables
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

variable "enable_account_factory_trigger" {
  type    = bool
  default = false
}

variable "enable_iam_resources" {
  type    = bool
  default = false
}

variable "enable_customizations" {
  type    = bool
  default = false
}

variable "enable_acm" {
  type    = bool
  default = false
}

# ── Account Factory Trigger ──────────────────────────────────────────────────

variable "github_repo" {
  type    = string
  default = ""
}

variable "github_workflow_id" {
  type    = string
  default = "account-setup.yml"
}

variable "github_ref" {
  type    = string
  default = "main"
}

variable "github_token_secret_arn" {
  type    = string
  default = null
}

variable "account_creation_notification_emails" {
  type    = list(string)
  default = []
}

variable "skip_account_names" {
  description = "Account names to skip in account factory trigger (foundational accounts)."
  type        = list(string)
  default     = ["log-archive", "audit", "shared-services"]
}

# ── IAM Resources ────────────────────────────────────────────────────────────

variable "iam_account_alias" {
  type    = string
  default = null
}

variable "iam_users" {
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
  type = map(object({
    path            = optional(string, "/")
    policies        = optional(list(string), [])
    inline_policies = optional(map(string), {})
  }))
  default = {}
}

variable "iam_roles" {
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
  type = map(object({
    path        = optional(string, "/")
    description = optional(string, "")
    policy      = string
  }))
  default = {}
}

variable "iam_saml_providers" {
  type = map(object({
    saml_metadata_document = string
  }))
  default = {}
}

variable "iam_instance_profiles" {
  type = map(object({
    role_name = string
    path      = optional(string, "/")
  }))
  default = {}
}

# ── Customizations ───────────────────────────────────────────────────────────

variable "cloudformation_stacks" {
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
  type    = any
  default = {}
}

variable "network_load_balancers" {
  type    = any
  default = {}
}

variable "launch_templates" {
  type    = any
  default = {}
}

variable "autoscaling_groups" {
  type    = any
  default = {}
}

# ── ACM ──────────────────────────────────────────────────────────────────────

variable "acm_certificates" {
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
