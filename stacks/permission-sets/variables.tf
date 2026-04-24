###############################################################################
# SSO Permission Sets — variables
###############################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "permission_sets" {
  description = "Map of SSO permission sets with customer-managed and AWS-managed policy attachments"
  type = map(object({
    name             = string
    description      = optional(string, "")
    session_duration = optional(string, "PT4H")
    customer_managed_policies = optional(list(object({
      name = string
      path = optional(string, "/")
    })), [])
    aws_managed_policies = optional(list(string), [])
  }))
}

variable "tags" {
  description = "Tags applied to permission sets"
  type        = map(string)
  default     = {}
}
