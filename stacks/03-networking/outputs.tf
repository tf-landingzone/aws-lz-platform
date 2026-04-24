################################################################################
# 03-Networking — Outputs
################################################################################
# Consumed by downstream stacks (06-workload-support) via remote state.
################################################################################

output "vpc_ids" {
  description = "Map of VPC keys to VPC IDs."
  value       = module.networking.vpc_ids
}

output "subnet_ids" {
  description = "Map of subnet keys to subnet IDs."
  value       = module.networking.subnet_ids
}

output "subnet_arns" {
  description = "Map of subnet keys to subnet ARNs."
  value       = module.networking.subnet_arns
}

output "transit_gateway_ids" {
  description = "Map of TGW keys to TGW IDs."
  value       = module.networking.transit_gateway_ids
}

output "transit_gateway_arns" {
  description = "Map of TGW keys to TGW ARNs."
  value       = module.networking.transit_gateway_arns
}

output "ram_share_arns" {
  description = "Map of RAM share keys to share ARNs."
  value       = { for k, v in aws_ram_resource_share.this : k => v.arn }
}

output "networking" {
  description = "Full networking module outputs."
  value       = module.networking
}
