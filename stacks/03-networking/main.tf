################################################################################
# 03-Networking — Main
################################################################################
# Networking infrastructure: VPCs, TGW, VPN, DX, Firewall, DNS, IPAM.
# Shared to workload accounts via AWS RAM.
# Independent state — changing a VPC doesn't replan security services.
################################################################################

module "networking" {
  source = "../../modules/networking"

  create = true
  tags   = local.common_tags

  delete_default_vpcs     = var.net_delete_default_vpcs
  ipam                    = var.net_ipam
  dhcp_options_sets       = var.net_dhcp_options_sets
  prefix_lists            = var.net_prefix_lists
  vpcs                    = var.net_vpcs
  vpc_peering             = var.net_vpc_peering
  transit_gateways        = var.net_transit_gateways
  transit_gateway_peering = var.net_transit_gateway_peering
  customer_gateways       = var.net_customer_gateways
  vpn_connections         = var.net_vpn_connections
  dx_gateways             = var.net_dx_gateways
  network_firewalls       = var.net_network_firewalls
  gateway_load_balancers  = var.net_gateway_load_balancers
  route53_resolver        = var.net_route53_resolver
}

################################################################################
# AWS RAM — Share networking resources with workload accounts/OUs
################################################################################

resource "aws_ram_resource_share" "this" {
  for_each = var.ram_shares

  name                      = each.value.name
  allow_external_principals = each.value.allow_external_principals

  tags = merge(local.common_tags, { Name = each.value.name })
}

# Share with OUs or accounts
resource "aws_ram_principal_association" "this" {
  for_each = merge([
    for share_key, share in var.ram_shares : {
      for idx, principal in share.principals :
      "${share_key}/${idx}" => {
        share_key = share_key
        principal = principal
      }
    }
  ]...)

  resource_share_arn = aws_ram_resource_share.this[each.value.share_key].arn
  principal          = each.value.principal
}

# Share explicit resource ARNs
resource "aws_ram_resource_association" "arns" {
  for_each = merge([
    for share_key, share in var.ram_shares : {
      for idx, arn in share.resource_arns :
      "${share_key}/arn-${idx}" => {
        share_key    = share_key
        resource_arn = arn
      }
    }
  ]...)

  resource_share_arn = aws_ram_resource_share.this[each.value.share_key].arn
  resource_arn       = each.value.resource_arn
}

# Share subnets by key (resolves from networking module outputs)
resource "aws_ram_resource_association" "subnets" {
  for_each = merge([
    for share_key, share in var.ram_shares : {
      for subnet_key in share.shared_subnet_keys :
      "${share_key}/subnet-${subnet_key}" => {
        share_key  = share_key
        subnet_key = subnet_key
      }
    }
  ]...)

  resource_share_arn = aws_ram_resource_share.this[each.value.share_key].arn
  resource_arn       = module.networking.subnet_arns[each.value.subnet_key]
}

# Share transit gateways by key
resource "aws_ram_resource_association" "tgw" {
  for_each = merge([
    for share_key, share in var.ram_shares : {
      for tgw_key in share.shared_tgw_keys :
      "${share_key}/tgw-${tgw_key}" => {
        share_key = share_key
        tgw_key   = tgw_key
      }
    }
  ]...)

  resource_share_arn = aws_ram_resource_share.this[each.value.share_key].arn
  resource_arn       = module.networking.transit_gateway_arns[each.value.tgw_key]
}
