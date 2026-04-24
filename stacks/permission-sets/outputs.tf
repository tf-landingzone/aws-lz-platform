###############################################################################
# SSO Permission Sets — outputs
###############################################################################

output "permission_set_arns" {
  description = "ARNs of created permission sets"
  value       = { for k, ps in aws_ssoadmin_permission_set.this : k => ps.arn }
}

output "permission_set_names" {
  description = "Names of created permission sets"
  value       = { for k, ps in aws_ssoadmin_permission_set.this : k => ps.name }
}
