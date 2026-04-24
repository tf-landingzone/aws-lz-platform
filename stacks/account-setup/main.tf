###############################################################################
# Account Setup — push IAM policies + SSO assignment + security baseline
###############################################################################
# Pipeline-driven: resolve_account.py outputs JSON → written to tfvars.json
# No manual tfvars editing — everything is dynamic from account_policy_map.yaml
#
# What happens:
#   1. Assumes role into target account → creates IAM policies (from JSON files)
#   2. Looks up existing SSO permission set + existing IdP group
#   3. Creates account assignment: group + permission set → this account
#   4. Applies security hardening baseline (password policy, EBS, S3, analyzer)
###############################################################################

locals {
  # Read policy JSON files and pass content to the module
  policies_with_content = {
    for k, v in var.policies : k => {
      name    = v.name
      content = file("${path.root}/../../${v.file}")
    }
  }

  default_tags = merge(var.tags, {
    AccountId   = var.account_id
    AccountName = var.account_name
    Environment = var.environment
  })
}

module "baseline" {
  source = "../../modules/account-baseline"

  providers = {
    aws.target = aws.target
    aws.sso    = aws
  }

  account_id  = var.account_id
  policies    = local.policies_with_content
  assignments = var.assignments
  tags        = local.default_tags

  # Security hardening — defaults applied unless overridden per-environment
  enable_password_policy       = var.security_baseline.enable_password_policy
  password_policy              = var.security_baseline.password_policy
  enable_ebs_encryption        = var.security_baseline.enable_ebs_encryption
  enable_s3_public_access_block = var.security_baseline.enable_s3_public_access_block
  enable_access_analyzer       = var.security_baseline.enable_access_analyzer
}
