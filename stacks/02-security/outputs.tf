################################################################################
# 02-Security — Outputs
################################################################################

output "permission_set_arns" {
  description = "Map of permission set keys to ARNs."
  value       = var.enable_identity_center ? module.identity_center[0].permission_set_arns : {}
}

output "group_ids" {
  description = "Resolved IdP group IDs."
  value       = var.enable_identity_center ? module.identity_center[0].group_ids : {}
}

output "security_summary" {
  description = "Summary of org-level security services."
  value       = var.enable_security_baseline ? module.security_baseline[0].security_summary : {}
}

output "config_rules" {
  description = "Config Rules module outputs."
  value       = var.enable_config_rules ? module.config_rules[0] : null
}

output "inspector" {
  description = "Inspector module outputs."
  value       = var.enable_inspector ? module.inspector[0] : null
}

output "macie" {
  description = "Macie module outputs."
  value       = var.enable_macie ? module.macie[0] : null
}

output "detective" {
  description = "Detective module outputs."
  value       = var.enable_detective ? module.detective[0] : null
}

output "audit_manager" {
  description = "Audit Manager module outputs."
  value       = var.enable_audit_manager ? module.audit_manager[0] : null
}
