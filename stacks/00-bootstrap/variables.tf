variable "org" {
  description = "Organization short name (e.g. acme)"
  type        = string
}

variable "program" {
  description = "Program or project name (e.g. lz)"
  type        = string
  default     = "lz"
}

variable "owner" {
  description = "Team or person owning this infrastructure"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing allocation"
  type        = string
  default     = ""
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "extra_tags" {
  description = "Additional tags to merge into common_tags"
  type        = map(string)
  default     = {}
}

variable "create_state_backend" {
  description = "Create S3 + DynamoDB for remote state"
  type        = bool
  default     = true
}

variable "enable_state_replication" {
  description = "Replicate the state bucket to a DR region (recommended for prod)."
  type        = bool
  default     = true
}

variable "dr_region" {
  description = "Destination region for state bucket cross-region replication."
  type        = string
  default     = "us-west-2"
}

