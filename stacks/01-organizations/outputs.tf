################################################################################
# 01-Organizations — Outputs
################################################################################
# These outputs are consumed by downstream stacks via terraform_remote_state.
################################################################################

output "organizational_units" {
  description = "All OUs created."
  value       = module.organizations.organizational_units
}

output "ou_ids" {
  description = "Map of OU keys to OU IDs."
  value       = module.organizations.ou_ids
}

output "account_ids" {
  description = "Map of account keys to account IDs."
  value       = module.organizations.account_ids
}

output "scp_ids" {
  description = "Map of SCP keys to policy IDs."
  value       = module.governance.scp_ids
}

output "service_control_policies" {
  description = "SCPs created."
  value       = module.governance.service_control_policies
}
