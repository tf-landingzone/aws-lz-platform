#!/usr/bin/env python3
"""
Generate terraform.tfvars for the landing-zone stack from config/landing-zone.yaml.

Usage:
    python3 generate_landing_zone_tfvars.py [--config CONFIG_PATH] [--output OUTPUT_PATH]

Defaults:
    --config  config/landing-zone.yaml
    --output  stacks/landing-zone/terraform.tfvars
"""

import argparse
import json
import sys
from pathlib import Path

import yaml

from hcl_writer import write_tfvars


def load_config(path: str) -> dict:
    """Load and validate the YAML configuration file."""
    config_path = Path(path)
    if not config_path.exists():
        print(f"Error: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path, encoding="utf-8") as f:
        config = yaml.safe_load(f)

    if not isinstance(config, dict):
        print("Error: Config file must be a YAML mapping", file=sys.stderr)
        sys.exit(1)

    return config


def resolve_content_files(policies_dict: dict, base_dir: Path) -> dict:
    """
    For any policy entry that has a content_file path but no inline content,
    read the file and replace with inline content so Terraform never needs to
    call file() at plan/apply time (avoiding cross-module path ambiguity).

    Paths in content_file are resolved relative to base_dir (repo root).
    """
    resolved = {}
    for key, policy in policies_dict.items():
        if not isinstance(policy, dict):
            resolved[key] = policy
            continue
        policy = dict(policy)
        content_file = policy.get("content_file")
        if content_file and not policy.get("content"):
            target = base_dir / content_file
            if target.exists():
                policy["content"] = target.read_text(encoding="utf-8").strip()
                del policy["content_file"]
            else:
                print(
                    f"Warning: content_file not found: {target} (keeping as-is)",
                    file=sys.stderr,
                )
        resolved[key] = policy
    return resolved


def build_tfvars(config: dict, base_dir: Path | None = None) -> dict:
    """Transform YAML config into flat Terraform variable structure."""
    g = config.get("global", {})
    features = config.get("features", {})
    org_cfg = config.get("organizations", {})
    gov_cfg = config.get("governance", {})
    ic_cfg = config.get("identity_center", {})
    sec_cfg = config.get("security_baseline", {})
    budget_cfg = config.get("budget_alerts", {})
    trigger_cfg = config.get("account_factory_trigger", {})
    net_cfg = config.get("networking", {})
    log_cfg = config.get("centralized_logging", {})
    cfgrules_cfg = config.get("config_rules", {})
    kms_cfg = config.get("kms", {})
    macie_cfg = config.get("macie", {})
    detective_cfg = config.get("detective", {})
    audit_cfg = config.get("audit_manager", {})
    iam_cfg = config.get("iam_resources", {})
    cust_cfg = config.get("customizations", {})
    ct_cfg = config.get("control_tower", {})
    ssm_cfg = config.get("ssm", {})
    backup_cfg = config.get("backup", {})
    cost_cfg = config.get("cost_reporting", {})

    tfvars = {}

    # ── Global ───────────────────────────────────────────────────────────
    tfvars["org"] = g.get("org", "")
    tfvars["program"] = g.get("program", "lz")
    tfvars["primary_region"] = g.get("primary_region", "us-east-1")
    tfvars["owner"] = g.get("owner", "platform-team")
    tfvars["cost_center"] = g.get("cost_center", "")
    tfvars["extra_tags"] = g.get("extra_tags", {})

    # ── Feature Flags ────────────────────────────────────────────────────
    tfvars["enable_organizations"] = features.get("organizations", True)
    tfvars["enable_governance"] = features.get("governance", True)
    tfvars["enable_identity_center"] = features.get("identity_center", True)
    tfvars["enable_security_baseline"] = features.get("security_baseline", True)
    tfvars["enable_account_baselines"] = features.get("account_baselines", False)
    tfvars["enable_budget_alerts"] = features.get("budget_alerts", True)
    tfvars["enable_account_factory_trigger"] = features.get(
        "account_factory_trigger", trigger_cfg.get("enabled", False)
    )
    tfvars["enable_networking"] = features.get("networking", False)
    tfvars["enable_centralized_logging"] = features.get("centralized_logging", False)
    tfvars["enable_config_rules"] = features.get("config_rules", False)
    tfvars["enable_kms"] = features.get("kms", False)
    tfvars["enable_macie"] = features.get("macie", False)
    tfvars["enable_detective"] = features.get("detective", False)
    tfvars["enable_audit_manager"] = features.get("audit_manager", False)
    tfvars["enable_iam_resources"] = features.get("iam_resources", False)
    tfvars["enable_customizations"] = features.get("customizations", False)
    tfvars["enable_control_tower"] = features.get("control_tower", False)
    tfvars["enable_ssm"] = features.get("ssm", False)
    tfvars["enable_backup"] = features.get("backup", False)
    tfvars["enable_cost_reporting"] = features.get("cost_reporting", False)

    # ── Organizations ────────────────────────────────────────────────────
    tfvars["manage_organization"] = org_cfg.get("manage_organization", False)
    tfvars["feature_set"] = org_cfg.get("feature_set", "ALL")
    tfvars["organizational_units"] = org_cfg.get("organizational_units", {})
    tfvars["accounts"] = org_cfg.get("accounts", {})
    tfvars["delegated_administrators"] = org_cfg.get("delegated_administrators", {})

    # ── Governance ───────────────────────────────────────────────────────
    raw_scps = gov_cfg.get("service_control_policies", {})
    raw_tag_policies = gov_cfg.get("tag_policies", {})
    raw_backup_policies = gov_cfg.get("backup_policies", {})
    raw_ai_optout = gov_cfg.get("ai_services_opt_out_policies", {})
    if base_dir is not None:
        tfvars["service_control_policies"] = resolve_content_files(raw_scps, base_dir)
        tfvars["tag_policies"] = resolve_content_files(raw_tag_policies, base_dir)
        tfvars["backup_policies"] = resolve_content_files(raw_backup_policies, base_dir)
        tfvars["ai_services_opt_out_policies"] = resolve_content_files(raw_ai_optout, base_dir)
    else:
        tfvars["service_control_policies"] = raw_scps
        tfvars["tag_policies"] = raw_tag_policies
        tfvars["backup_policies"] = raw_backup_policies
        tfvars["ai_services_opt_out_policies"] = raw_ai_optout

    # ── Identity Center ──────────────────────────────────────────────────
    tfvars["group_lookups"] = ic_cfg.get("group_lookups", {})
    tfvars["permission_sets"] = ic_cfg.get("permission_sets", {})
    tfvars["account_assignments"] = ic_cfg.get("account_assignments", {})
    tfvars["access_control_attributes"] = ic_cfg.get("access_control_attributes", [])

    # ── Security Baseline ────────────────────────────────────────────────
    tfvars["org_cloudtrail"] = sec_cfg.get("org_cloudtrail", {})
    tfvars["config_aggregator"] = sec_cfg.get("config_aggregator", {})
    tfvars["guardduty_org"] = sec_cfg.get("guardduty_org", {})
    tfvars["securityhub_org"] = sec_cfg.get("securityhub_org", {})
    tfvars["enable_org_access_analyzer"] = sec_cfg.get("enable_org_access_analyzer", False)
    tfvars["org_access_analyzer_name"] = sec_cfg.get("org_access_analyzer_name", "org-access-analyzer")

    # ── Budget Alerts ────────────────────────────────────────────────────
    tfvars["notification_topics"] = budget_cfg.get("notification_topics", {})
    tfvars["budgets"] = budget_cfg.get("budgets", {})
    tfvars["anomaly_monitors"] = budget_cfg.get("anomaly_monitors", {})
    tfvars["anomaly_subscriptions"] = budget_cfg.get("anomaly_subscriptions", {})

    # ── Account Factory Trigger ──────────────────────────────────────────
    tfvars["github_repo"] = trigger_cfg.get("github_repo", "")
    tfvars["github_workflow_id"] = trigger_cfg.get("github_workflow_id", "account-setup.yml")
    tfvars["github_ref"] = trigger_cfg.get("github_ref", "main")
    tfvars["github_token_secret_arn"] = trigger_cfg.get("github_token_secret_arn", "")
    tfvars["account_creation_notification_emails"] = trigger_cfg.get("notification_emails", [])
    tfvars["skip_account_names"] = trigger_cfg.get("skip_account_names", ["log-archive", "audit", "shared-services"])

    # ── Networking ───────────────────────────────────────────────────────
    tfvars["net_delete_default_vpcs"] = net_cfg.get("delete_default_vpcs", False)
    tfvars["net_ipam"] = net_cfg.get("ipam", {})
    tfvars["net_dhcp_options_sets"] = net_cfg.get("dhcp_options_sets", {})
    tfvars["net_prefix_lists"] = net_cfg.get("prefix_lists", {})
    tfvars["net_vpcs"] = net_cfg.get("vpcs", {})
    tfvars["net_vpc_peering"] = net_cfg.get("vpc_peering", {})
    tfvars["net_transit_gateways"] = net_cfg.get("transit_gateways", {})
    tfvars["net_transit_gateway_peering"] = net_cfg.get("transit_gateway_peering", {})
    tfvars["net_customer_gateways"] = net_cfg.get("customer_gateways", {})
    tfvars["net_vpn_connections"] = net_cfg.get("vpn_connections", {})
    tfvars["net_dx_gateways"] = net_cfg.get("dx_gateways", {})
    tfvars["net_network_firewalls"] = net_cfg.get("network_firewalls", {})
    tfvars["net_gateway_load_balancers"] = net_cfg.get("gateway_load_balancers", {})
    tfvars["net_route53_resolver"] = net_cfg.get("route53_resolver", {})

    # ── Centralized Logging ──────────────────────────────────────────────
    tfvars["central_log_bucket"] = log_cfg.get("central_log_bucket", {"bucket_name": "central-logs"})
    tfvars["log_access_log_bucket"] = log_cfg.get("access_log_bucket", {"bucket_name": "central-access-logs"})
    tfvars["cloudwatch_to_s3"] = log_cfg.get("cloudwatch_to_s3", {})
    tfvars["session_manager_logging"] = log_cfg.get("session_manager_logging", {})

    # ── Config Rules ─────────────────────────────────────────────────────
    tfvars["config_recorder"] = cfgrules_cfg.get("config_recorder", {})
    tfvars["lz_config_rules"] = cfgrules_cfg.get("rules", {})
    tfvars["config_remediations"] = cfgrules_cfg.get("remediations", {})
    tfvars["org_config_rules"] = cfgrules_cfg.get("org_rules", {})
    tfvars["conformance_packs"] = cfgrules_cfg.get("conformance_packs", {})
    tfvars["org_conformance_packs"] = cfgrules_cfg.get("org_conformance_packs", {})
    tfvars["lz_config_aggregator"] = cfgrules_cfg.get("aggregator", {})

    # ── KMS ──────────────────────────────────────────────────────────────
    tfvars["kms_keys"] = kms_cfg.get("keys", {})

    # ── Macie ────────────────────────────────────────────────────────────
    tfvars["macie_admin_account_id"] = macie_cfg.get("admin_account_id")
    tfvars["macie_finding_frequency"] = macie_cfg.get("finding_frequency", "SIX_HOURS")
    tfvars["macie_member_accounts"] = macie_cfg.get("member_accounts", {})
    tfvars["macie_classification_jobs"] = macie_cfg.get("classification_jobs", {})
    tfvars["macie_custom_data_identifiers"] = macie_cfg.get("custom_data_identifiers", {})

    # ── Detective ────────────────────────────────────────────────────────
    tfvars["detective_admin_account_id"] = detective_cfg.get("admin_account_id")
    tfvars["detective_member_accounts"] = detective_cfg.get("member_accounts", {})

    # ── Audit Manager ────────────────────────────────────────────────────
    tfvars["audit_manager_admin_account_id"] = audit_cfg.get("admin_account_id")
    tfvars["audit_manager_kms_key_id"] = audit_cfg.get("kms_key_id")
    tfvars["audit_manager_s3_bucket"] = audit_cfg.get("s3_bucket")
    tfvars["audit_manager_s3_prefix"] = audit_cfg.get("s3_prefix", "audit-manager")
    tfvars["audit_manager_assessments"] = audit_cfg.get("assessments", {})
    tfvars["audit_manager_custom_frameworks"] = audit_cfg.get("custom_frameworks", {})
    tfvars["audit_manager_custom_controls"] = audit_cfg.get("custom_controls", {})

    # ── IAM Resources ────────────────────────────────────────────────────
    tfvars["iam_account_alias"] = iam_cfg.get("account_alias")
    tfvars["iam_users"] = iam_cfg.get("users", {})
    tfvars["iam_groups"] = iam_cfg.get("groups", {})
    tfvars["iam_roles"] = iam_cfg.get("roles", {})
    tfvars["iam_policies"] = iam_cfg.get("policies", {})
    tfvars["iam_saml_providers"] = iam_cfg.get("saml_providers", {})
    tfvars["iam_instance_profiles"] = iam_cfg.get("instance_profiles", {})

    # ── Customizations ───────────────────────────────────────────────────
    tfvars["cloudformation_stacks"] = cust_cfg.get("cloudformation_stacks", {})
    tfvars["cloudformation_stacksets"] = cust_cfg.get("cloudformation_stacksets", {})
    tfvars["service_catalog_portfolios"] = cust_cfg.get("service_catalog_portfolios", {})
    tfvars["application_load_balancers"] = cust_cfg.get("application_load_balancers", {})
    tfvars["network_load_balancers"] = cust_cfg.get("network_load_balancers", {})
    tfvars["launch_templates"] = cust_cfg.get("launch_templates", {})
    tfvars["autoscaling_groups"] = cust_cfg.get("autoscaling_groups", {})

    # ── Control Tower ────────────────────────────────────────────────────
    tfvars["ct_controls"] = ct_cfg.get("controls", {})
    tfvars["ct_quarantine_scp"] = ct_cfg.get("quarantine_scp", {})
    tfvars["ct_landing_zone"] = ct_cfg.get("landing_zone", {})

    # ── SSM ──────────────────────────────────────────────────────────────
    tfvars["ssm_parameters"] = ssm_cfg.get("parameters", {})
    tfvars["ssm_documents"] = ssm_cfg.get("documents", {})
    tfvars["ssm_associations"] = ssm_cfg.get("associations", {})
    tfvars["ssm_maintenance_windows"] = ssm_cfg.get("maintenance_windows", {})
    tfvars["ssm_patch_baselines"] = ssm_cfg.get("patch_baselines", {})
    tfvars["ssm_default_patch_baselines"] = ssm_cfg.get("default_patch_baselines", {})

    # ── Backup ───────────────────────────────────────────────────────────
    tfvars["backup_region_settings"] = backup_cfg.get("region_settings", {})
    tfvars["backup_vaults"] = backup_cfg.get("vaults", {})
    tfvars["backup_plans"] = backup_cfg.get("plans", {})
    tfvars["backup_org_policy"] = backup_cfg.get("org_policy", {})

    # ── Cost Reporting ───────────────────────────────────────────────────
    tfvars["cost_usage_reports"] = cost_cfg.get("cost_usage_reports", {})
    tfvars["cost_anomaly_monitors"] = cost_cfg.get("anomaly_monitors", {})
    tfvars["cost_anomaly_subscriptions"] = cost_cfg.get("anomaly_subscriptions", {})
    tfvars["cost_budgets"] = cost_cfg.get("budgets", {})

    return tfvars


def main():
    parser = argparse.ArgumentParser(
        description="Generate terraform.tfvars from landing-zone YAML config"
    )
    parser.add_argument(
        "--config",
        default="config/landing-zone.yaml",
        help="Path to YAML config (default: config/landing-zone.yaml)",
    )
    parser.add_argument(
        "--output",
        default="stacks/landing-zone/terraform.tfvars",
        help="Output path (default: stacks/landing-zone/terraform.tfvars)",
    )
    args = parser.parse_args()

    config = load_config(args.config)
    base_dir = Path(args.config).resolve().parent.parent
    tfvars = build_tfvars(config, base_dir=base_dir)

    output_path = Path(args.output)
    write_tfvars(tfvars, output_path)

    print(f"Generated {output_path} ({len(tfvars)} variables)")


if __name__ == "__main__":
    main()
