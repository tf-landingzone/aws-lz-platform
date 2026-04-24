###############################################################################
# Account Setup — outputs
###############################################################################

output "account_id" {
  description = "Target account ID"
  value       = var.account_id
}

output "account_name" {
  description = "Target account name"
  value       = var.account_name
}

output "environment" {
  description = "Account environment classification"
  value       = var.environment
}

output "policy_arns" {
  description = "IAM policy ARNs created in the target account"
  value       = module.baseline.policy_arns
}

output "account_assignments" {
  description = "SSO account assignments (group → permission set → account)"
  value       = module.baseline.account_assignments
}

output "security_baseline" {
  description = "Security baseline status for the account"
  value       = module.baseline.security_baseline
}
