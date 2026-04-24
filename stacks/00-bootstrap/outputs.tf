output "prefix" {
  description = "Naming prefix for all resources"
  value       = local.prefix
}

output "common_tags" {
  description = "Standard tags applied to all resources"
  value       = local.common_tags
}

output "management_account_id" {
  description = "AWS management account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "org_id" {
  description = "AWS Organizations ID"
  value       = data.aws_organizations_organization.current.id
}

output "state_bucket" {
  description = "S3 bucket for Terraform state"
  value       = var.create_state_backend ? aws_s3_bucket.state[0].id : null
}

output "lock_table" {
  description = "DynamoDB table for state locking"
  value       = var.create_state_backend ? aws_dynamodb_table.lock[0].name : null
}

output "deploy_run_state_table" {
  description = "DynamoDB table for deploy_accounts.py run state (resume-on-failure)"
  value       = var.create_state_backend ? aws_dynamodb_table.deploy_run_state[0].name : null
}

output "state_replica_bucket" {
  description = "DR replica bucket for Terraform state (in dr_region)"
  value = (
    var.create_state_backend && var.enable_state_replication
    ? aws_s3_bucket.state_replica[0].id
    : null
  )
}

output "dr_region" {
  description = "Region holding the state replica bucket"
  value       = var.dr_region
}
