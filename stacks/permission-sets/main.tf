###############################################################################
# SSO Permission Sets — one-time setup
###############################################################################
# Creates permission sets and attaches customer-managed policy references.
# These reference IAM policies BY NAME — the actual policies must exist in
# each target account (pushed by the account-setup pipeline).
#
# How it works with IdP groups:
#   1. IdP (Azure AD / Okta) syncs groups to IAM Identity Center via SCIM
#   2. Permission sets here define what level of access
#   3. Customer-managed policy attachments reference IAM policies by name
#   4. Account assignments (done per-account) link: group + PS → account
#   5. When an IdP user accesses the account, SSO resolves the PS to the
#      customer-managed policy that exists IN that target account
###############################################################################

data "aws_ssoadmin_instances" "this" {}

locals {
  sso_instance_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]

  # Flatten: permission-set → customer-managed-policy pairs
  ps_cmp_pairs = flatten([
    for ps_key, ps in var.permission_sets : [
      for pol in ps.customer_managed_policies : {
        key         = "${ps_key}__${replace(lower(pol.name), "/[^a-z0-9]/", "_")}"
        ps_key      = ps_key
        policy_name = pol.name
        policy_path = pol.path
      }
    ]
  ])

  # Flatten: permission-set → AWS-managed-policy pairs
  ps_amp_pairs = flatten([
    for ps_key, ps in var.permission_sets : [
      for arn in ps.aws_managed_policies : {
        key    = "${ps_key}__${element(split("/", arn), length(split("/", arn)) - 1)}"
        ps_key = ps_key
        arn    = arn
      }
    ]
  ])
}

# ── Permission Sets ──────────────────────────────────────────────────────────

resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  instance_arn     = local.sso_instance_arn
  name             = each.value.name
  description      = each.value.description
  session_duration = each.value.session_duration

  tags = var.tags
}

# ── Customer-Managed Policy Attachments (reference by NAME, not ARN) ─────────

resource "aws_ssoadmin_customer_managed_policy_attachment" "this" {
  for_each = { for p in local.ps_cmp_pairs : p.key => p }

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.ps_key].arn

  customer_managed_policy_reference {
    name = each.value.policy_name
    path = each.value.policy_path
  }
}

# ── AWS-Managed Policy Attachments (optional, e.g. ReadOnlyAccess) ───────────

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = { for p in local.ps_amp_pairs : p.key => p }

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.ps_key].arn
  managed_policy_arn = each.value.arn
}
