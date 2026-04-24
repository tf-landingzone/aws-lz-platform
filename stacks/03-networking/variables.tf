################################################################################
# 03-Networking — Variables
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

# ── Networking ───────────────────────────────────────────────────────────────

variable "net_delete_default_vpcs" {
  type    = bool
  default = false
}

variable "net_ipam" {
  type = object({
    enabled     = optional(bool, false)
    description = optional(string, "Organization IPAM")
    operating_regions = optional(list(object({
      region_name = string
    })), [])
    scopes = optional(map(object({ description = optional(string, "") })), {})
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
  type    = any
  default = {}
}

variable "net_prefix_lists" {
  type    = any
  default = {}
}

variable "net_vpcs" {
  type    = any
  default = {}
}

variable "net_vpc_peering" {
  type    = any
  default = {}
}

variable "net_transit_gateways" {
  type    = any
  default = {}
}

variable "net_transit_gateway_peering" {
  type    = any
  default = {}
}

variable "net_customer_gateways" {
  type    = any
  default = {}
}

variable "net_vpn_connections" {
  type    = any
  default = {}
}

variable "net_dx_gateways" {
  type    = any
  default = {}
}

variable "net_network_firewalls" {
  type    = any
  default = {}
}

variable "net_gateway_load_balancers" {
  type    = any
  default = {}
}

variable "net_route53_resolver" {
  type    = any
  default = {}
}

# ── RAM Sharing ──────────────────────────────────────────────────────────────

variable "ram_shares" {
  description = "AWS RAM resource shares for sharing networking resources."
  type = map(object({
    name                      = string
    allow_external_principals = optional(bool, false)
    principals                = optional(list(string), [])
    resource_arns             = optional(list(string), [])
    shared_subnet_keys        = optional(list(string), [])
    shared_tgw_keys           = optional(list(string), [])
  }))
  default = {}
}
