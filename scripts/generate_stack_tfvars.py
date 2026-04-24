#!/usr/bin/env python3
"""
Generate terraform.tfvars for each split stack from config/ YAML files.

Usage:
    # Generate for a specific stack:
    python3 generate_stack_tfvars.py --stack 01-organizations

    # Generate for all stacks:
    python3 generate_stack_tfvars.py --all

    # Custom paths:
    python3 generate_stack_tfvars.py --stack 03-networking --global-config config/global.yaml

Each stack reads config/global.yaml + config/<stack-name>.yaml and produces
stacks/<stack-name>/terraform.tfvars.
"""

import argparse
import json
import sys
from pathlib import Path

import yaml

from hcl_writer import write_tfvars

STACK_CONFIGS = {
    "01-organizations": "config/01-organizations.yaml",
    "02-security": "config/02-security.yaml",
    "03-networking": "config/03-networking.yaml",
    "04-logging": "config/04-logging.yaml",
    "05-operations": "config/05-operations.yaml",
    "06-workload-support": "config/06-workload-support.yaml",
}


def load_yaml(path: str) -> dict:
    """Load a YAML file, returning empty dict if not found."""
    p = Path(path)
    if not p.exists():
        print(f"Warning: Config file not found: {p}", file=sys.stderr)
        return {}
    with open(p, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        print(f"Error: {p} must be a YAML mapping", file=sys.stderr)
        sys.exit(1)
    return data


def build_global_vars(g: dict) -> dict:
    """Extract global variables shared by all stacks."""
    return {
        "org": g.get("org", ""),
        "program": g.get("program", "lz"),
        "primary_region": g.get("primary_region", "us-east-1"),
        "owner": g.get("owner", "platform-team"),
        "cost_center": g.get("cost_center", ""),
        "extra_tags": g.get("extra_tags", {}),
    }


def build_01_organizations(cfg: dict) -> dict:
    """Build tfvars for 01-organizations stack."""
    org = cfg.get("organizations", {})
    gov = cfg.get("governance", {})
    return {
        "manage_organization": org.get("manage_organization", False),
        "feature_set": org.get("feature_set", "ALL"),
        "organizational_units": org.get("organizational_units", {}),
        "accounts": org.get("accounts", {}),
        "delegated_administrators": org.get("delegated_administrators", {}),
        "service_control_policies": gov.get("service_control_policies", {}),
        "tag_policies": gov.get("tag_policies", {}),
        "backup_policies": gov.get("backup_policies", {}),
        "ai_services_opt_out_policies": gov.get("ai_services_opt_out_policies", {}),
    }


def build_02_security(cfg: dict) -> dict:
    """Build tfvars for 02-security stack."""
    ic = cfg.get("identity_center", {})
    sec = cfg.get("security_baseline", {})
    cr = cfg.get("config_rules", {})
    ct = cfg.get("control_tower", {})
    insp = cfg.get("inspector", {})
    macie = cfg.get("macie", {})
    det = cfg.get("detective", {})
    audit = cfg.get("audit_manager", {})

    return {
        # Feature flags
        "enable_identity_center": bool(ic.get("permission_sets") or ic.get("group_lookups")),
        "enable_security_baseline": any([
            sec.get("org_cloudtrail", {}).get("enabled"),
            sec.get("guardduty_org", {}).get("enabled"),
            sec.get("securityhub_org", {}).get("enabled"),
            sec.get("config_aggregator", {}).get("enabled"),
            sec.get("enable_org_access_analyzer"),
        ]),
        "enable_config_rules": bool(
            cr.get("config_recorder", {}).get("enabled")
            or cr.get("rules")
            or cr.get("org_rules")
        ),
        "enable_control_tower": bool(ct.get("controls") or ct.get("landing_zone", {}).get("enabled")),
        "enable_inspector": insp.get("admin_account_id") is not None,
        "enable_macie": macie.get("admin_account_id") is not None,
        "enable_detective": det.get("admin_account_id") is not None,
        "enable_audit_manager": audit.get("admin_account_id") is not None,
        # Identity Center
        "group_lookups": ic.get("group_lookups", {}),
        "permission_sets": ic.get("permission_sets", {}),
        "account_assignments": ic.get("account_assignments", {}),
        "access_control_attributes": ic.get("access_control_attributes", []),
        # Security Baseline
        "org_cloudtrail": sec.get("org_cloudtrail", {}),
        "config_aggregator": sec.get("config_aggregator", {}),
        "guardduty_org": sec.get("guardduty_org", {}),
        "securityhub_org": sec.get("securityhub_org", {}),
        "enable_org_access_analyzer": sec.get("enable_org_access_analyzer", False),
        "org_access_analyzer_name": sec.get("org_access_analyzer_name", "org-access-analyzer"),
        # Config Rules
        "config_recorder": cr.get("config_recorder", {}),
        "lz_config_rules": cr.get("rules", {}),
        "config_remediations": cr.get("remediations", {}),
        "org_config_rules": cr.get("org_rules", {}),
        "conformance_packs": cr.get("conformance_packs", {}),
        "org_conformance_packs": cr.get("org_conformance_packs", {}),
        "lz_config_aggregator": cr.get("aggregator", {}),
        # Control Tower
        "ct_controls": ct.get("controls", {}),
        "ct_quarantine_scp": ct.get("quarantine_scp", {}),
        "ct_landing_zone": ct.get("landing_zone", {}),
        # Inspector
        "inspector_admin_account_id": insp.get("admin_account_id"),
        "inspector_resource_types": insp.get("resource_types", ["EC2", "ECR"]),
        # Macie
        "macie_admin_account_id": macie.get("admin_account_id"),
        "macie_finding_frequency": macie.get("finding_frequency", "SIX_HOURS"),
        "macie_member_accounts": macie.get("member_accounts", {}),
        "macie_classification_jobs": macie.get("classification_jobs", {}),
        "macie_custom_data_identifiers": macie.get("custom_data_identifiers", {}),
        # Detective
        "detective_admin_account_id": det.get("admin_account_id"),
        "detective_member_accounts": det.get("member_accounts", {}),
        # Audit Manager
        "audit_manager_admin_account_id": audit.get("admin_account_id"),
        "audit_manager_kms_key_id": audit.get("kms_key_id"),
        "audit_manager_s3_bucket": audit.get("s3_bucket"),
        "audit_manager_s3_prefix": audit.get("s3_prefix", "audit-manager"),
        "audit_manager_assessments": audit.get("assessments", {}),
        "audit_manager_custom_frameworks": audit.get("custom_frameworks", {}),
        "audit_manager_custom_controls": audit.get("custom_controls", {}),
    }


def build_03_networking(cfg: dict) -> dict:
    """Build tfvars for 03-networking stack."""
    net = cfg.get("networking", {})
    return {
        "net_delete_default_vpcs": net.get("delete_default_vpcs", False),
        "net_ipam": net.get("ipam", {}),
        "net_dhcp_options_sets": net.get("dhcp_options_sets", {}),
        "net_prefix_lists": net.get("prefix_lists", {}),
        "net_vpcs": net.get("vpcs", {}),
        "net_vpc_peering": net.get("vpc_peering", {}),
        "net_transit_gateways": net.get("transit_gateways", {}),
        "net_transit_gateway_peering": net.get("transit_gateway_peering", {}),
        "net_customer_gateways": net.get("customer_gateways", {}),
        "net_vpn_connections": net.get("vpn_connections", {}),
        "net_dx_gateways": net.get("dx_gateways", {}),
        "net_network_firewalls": net.get("network_firewalls", {}),
        "net_gateway_load_balancers": net.get("gateway_load_balancers", {}),
        "net_route53_resolver": net.get("route53_resolver", {}),
        "ram_shares": cfg.get("ram_shares", {}),
    }


def build_04_logging(cfg: dict) -> dict:
    """Build tfvars for 04-logging stack."""
    log = cfg.get("centralized_logging", {})
    kms = cfg.get("kms", {})
    return {
        "enable_centralized_logging": log.get("central_log_bucket", {}).get("enabled", False),
        "enable_kms": bool(kms.get("keys")),
        "central_log_bucket": log.get("central_log_bucket", {"bucket_name": "central-logs"}),
        "log_access_log_bucket": log.get("access_log_bucket", {"bucket_name": "central-access-logs"}),
        "cloudwatch_to_s3": log.get("cloudwatch_to_s3", {}),
        "session_manager_logging": log.get("session_manager_logging", {}),
        "kms_keys": kms.get("keys", {}),
    }


def build_05_operations(cfg: dict) -> dict:
    """Build tfvars for 05-operations stack."""
    budget = cfg.get("budget_alerts", {})
    ssm = cfg.get("ssm", {})
    backup = cfg.get("backup", {})
    cost = cfg.get("cost_reporting", {})
    return {
        "enable_budget_alerts": bool(budget.get("budgets") or budget.get("notification_topics")),
        "enable_ssm": bool(ssm.get("parameters") or ssm.get("documents") or ssm.get("patch_baselines")),
        "enable_backup": bool(backup.get("vaults") or backup.get("plans")),
        "enable_cost_reporting": bool(cost.get("cost_usage_reports") or cost.get("anomaly_monitors")),
        # Budget
        "notification_topics": budget.get("notification_topics", {}),
        "budgets": budget.get("budgets", {}),
        "anomaly_monitors": budget.get("anomaly_monitors", {}),
        "anomaly_subscriptions": budget.get("anomaly_subscriptions", {}),
        # SSM
        "ssm_parameters": ssm.get("parameters", {}),
        "ssm_documents": ssm.get("documents", {}),
        "ssm_associations": ssm.get("associations", {}),
        "ssm_maintenance_windows": ssm.get("maintenance_windows", {}),
        "ssm_patch_baselines": ssm.get("patch_baselines", {}),
        "ssm_default_patch_baselines": ssm.get("default_patch_baselines", {}),
        # Backup
        "backup_region_settings": backup.get("region_settings", {}),
        "backup_vaults": backup.get("vaults", {}),
        "backup_plans": backup.get("plans", {}),
        "backup_org_policy": backup.get("org_policy", {}),
        # Cost Reporting
        "cost_usage_reports": cost.get("cost_usage_reports", {}),
        "cost_anomaly_monitors": cost.get("anomaly_monitors", {}),
        "cost_anomaly_subscriptions": cost.get("anomaly_subscriptions", {}),
        "cost_budgets": cost.get("budgets", {}),
    }


def build_06_workload_support(cfg: dict) -> dict:
    """Build tfvars for 06-workload-support stack."""
    trigger = cfg.get("account_factory_trigger", {})
    iam = cfg.get("iam_resources", {})
    cust = cfg.get("customizations", {})
    acm = cfg.get("acm", {})
    return {
        "enable_account_factory_trigger": trigger.get("enabled", False),
        "enable_iam_resources": bool(iam.get("users") or iam.get("groups") or iam.get("roles")),
        "enable_customizations": bool(cust.get("cloudformation_stacks") or cust.get("cloudformation_stacksets")),
        "enable_acm": bool(acm.get("certificates")),
        # Trigger
        "github_repo": trigger.get("github_repo", ""),
        "github_workflow_id": trigger.get("github_workflow_id", "account-setup.yml"),
        "github_ref": trigger.get("github_ref", "main"),
        "github_token_secret_arn": trigger.get("github_token_secret_arn"),
        "account_creation_notification_emails": trigger.get("notification_emails", []),
        # IAM
        "iam_account_alias": iam.get("account_alias"),
        "iam_users": iam.get("users", {}),
        "iam_groups": iam.get("groups", {}),
        "iam_roles": iam.get("roles", {}),
        "iam_policies": iam.get("policies", {}),
        "iam_saml_providers": iam.get("saml_providers", {}),
        "iam_instance_profiles": iam.get("instance_profiles", {}),
        # Customizations
        "cloudformation_stacks": cust.get("cloudformation_stacks", {}),
        "cloudformation_stacksets": cust.get("cloudformation_stacksets", {}),
        "service_catalog_portfolios": cust.get("service_catalog_portfolios", {}),
        "application_load_balancers": cust.get("application_load_balancers", {}),
        "network_load_balancers": cust.get("network_load_balancers", {}),
        "launch_templates": cust.get("launch_templates", {}),
        "autoscaling_groups": cust.get("autoscaling_groups", {}),
        # ACM
        "acm_certificates": acm.get("certificates", {}),
    }


BUILDERS = {
    "01-organizations": build_01_organizations,
    "02-security": build_02_security,
    "03-networking": build_03_networking,
    "04-logging": build_04_logging,
    "05-operations": build_05_operations,
    "06-workload-support": build_06_workload_support,
}


def generate_stack(stack_name: str, global_config_path: str) -> None:
    """Generate terraform.tfvars for a single stack."""
    if stack_name not in STACK_CONFIGS:
        print(f"Error: Unknown stack '{stack_name}'. Valid: {', '.join(STACK_CONFIGS.keys())}", file=sys.stderr)
        sys.exit(1)

    # Load configs
    global_cfg = load_yaml(global_config_path)
    stack_cfg = load_yaml(STACK_CONFIGS[stack_name])

    # Build tfvars
    tfvars = build_global_vars(global_cfg)
    builder = BUILDERS[stack_name]
    tfvars.update(builder(stack_cfg))

    # Write output
    output_path = Path(f"stacks/{stack_name}/terraform.tfvars")
    write_tfvars(tfvars, output_path)

    print(f"  {output_path} ({len(tfvars)} variables)")

    print(f"  {output_path} ({len(tfvars)} variables)")


def main():
    parser = argparse.ArgumentParser(
        description="Generate terraform.tfvars for split stacks"
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--stack",
        choices=list(STACK_CONFIGS.keys()),
        help="Generate for a specific stack",
    )
    group.add_argument(
        "--all",
        action="store_true",
        help="Generate for all stacks",
    )
    parser.add_argument(
        "--global-config",
        default="config/global.yaml",
        help="Path to global config (default: config/global.yaml)",
    )
    args = parser.parse_args()

    if args.all:
        print("Generating terraform.tfvars for all stacks:")
        for stack_name in STACK_CONFIGS:
            generate_stack(stack_name, args.global_config)
        print(f"\nDone. Generated {len(STACK_CONFIGS)} stack configs.")
    else:
        print(f"Generating terraform.tfvars.json for {args.stack}:")
        generate_stack(args.stack, args.global_config)


if __name__ == "__main__":
    main()
