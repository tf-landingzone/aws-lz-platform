################################################################################
# 01-Organizations — Main
################################################################################
# Foundation stack: OUs, accounts, governance (SCPs, tag policies).
# All other stacks read from this via terraform_remote_state.
################################################################################

module "organizations" {
  source = "../../modules/organizations"

  create = true
  tags   = local.common_tags

  manage_organization        = var.manage_organization
  feature_set                = var.feature_set
  enabled_service_principals = var.enabled_service_principals
  enabled_policy_types       = var.enabled_policy_types
  organizational_units       = var.organizational_units
  accounts                   = var.accounts
  delegated_administrators   = var.delegated_administrators
}

################################################################################
# Resolve OU keys + "root" flag to actual target IDs for policy attachments.
# This avoids hardcoded OU/root IDs in config YAML (which aren't known until
# organizations module is applied). Policies can reference OUs by their key.
################################################################################
locals {
  _ou_id_by_key = { for k, v in module.organizations.organizational_units : k => v.id }
  _root_id      = try(module.organizations.organization.root_id, null)

  _resolve_targets = {
    for pk, p in var.service_control_policies : pk => distinct(concat(
      p.target_ids,
      [for k in p.target_ou_keys : local._ou_id_by_key[k] if contains(keys(local._ou_id_by_key), k)],
      p.target_root && local._root_id != null ? [local._root_id] : [],
    ))
  }
  _resolve_tag_targets = {
    for pk, p in var.tag_policies : pk => distinct(concat(
      p.target_ids,
      [for k in p.target_ou_keys : local._ou_id_by_key[k] if contains(keys(local._ou_id_by_key), k)],
      p.target_root && local._root_id != null ? [local._root_id] : [],
    ))
  }
  _resolve_backup_targets = {
    for pk, p in var.backup_policies : pk => distinct(concat(
      p.target_ids,
      [for k in p.target_ou_keys : local._ou_id_by_key[k] if contains(keys(local._ou_id_by_key), k)],
      p.target_root && local._root_id != null ? [local._root_id] : [],
    ))
  }
  _resolve_aiopt_targets = {
    for pk, p in var.ai_services_opt_out_policies : pk => distinct(concat(
      p.target_ids,
      [for k in p.target_ou_keys : local._ou_id_by_key[k] if contains(keys(local._ou_id_by_key), k)],
      p.target_root && local._root_id != null ? [local._root_id] : [],
    ))
  }

  service_control_policies_resolved = {
    for k, v in var.service_control_policies : k => {
      name         = v.name
      description  = v.description
      content      = v.content
      content_file = v.content_file
      target_ids   = local._resolve_targets[k]
      tags         = v.tags
    }
  }
  tag_policies_resolved = {
    for k, v in var.tag_policies : k => {
      name         = v.name
      description  = v.description
      content      = v.content
      content_file = v.content_file
      target_ids   = local._resolve_tag_targets[k]
      tags         = v.tags
    }
  }
  backup_policies_resolved = {
    for k, v in var.backup_policies : k => {
      name         = v.name
      description  = v.description
      content      = v.content
      content_file = v.content_file
      target_ids   = local._resolve_backup_targets[k]
      tags         = v.tags
    }
  }
  ai_services_opt_out_policies_resolved = {
    for k, v in var.ai_services_opt_out_policies : k => {
      name         = v.name
      description  = v.description
      content      = v.content
      content_file = v.content_file
      target_ids   = local._resolve_aiopt_targets[k]
      tags         = v.tags
    }
  }
}

module "governance" {
  source = "../../modules/governance"

  create = true
  tags   = local.common_tags

  service_control_policies     = local.service_control_policies_resolved
  tag_policies                 = local.tag_policies_resolved
  backup_policies              = local.backup_policies_resolved
  ai_services_opt_out_policies = local.ai_services_opt_out_policies_resolved

  depends_on = [module.organizations]
}
