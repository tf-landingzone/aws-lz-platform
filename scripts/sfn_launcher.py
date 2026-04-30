#!/usr/bin/env python3
"""
sfn_launcher.py — starts a Step Functions execution for account provisioning.

Called by GitHub Actions workflows (account-setup.yml, drift-sweep.yml).
It assembles the job manifest, uploads it to S3, then starts the SFN execution.

Usage examples
--------------
# Single account, plan+apply:
python3 scripts/sfn_launcher.py \
    --state-machine-arn arn:aws:states:us-east-1:111111111111:stateMachine:lz-account-pipeline \
    --state-bucket acme-lz-terraform-state \
    --policy-map-local account_policy_map.yaml \
    --account-id 222222222222 \
    --account-name prod-app-001 \
    --wait

# Batch from --account-ids-file (a newline-separated list of "id,name" pairs):
python3 scripts/sfn_launcher.py \
    --state-machine-arn arn:... \
    --state-bucket acme-lz-terraform-state \
    --policy-map-local account_policy_map.yaml \
    --account-ids-file /tmp/accounts.txt \
    --environment production \
    --wait

# Drift sweep (all provisioned accounts from DynamoDB, plan-only):
python3 scripts/sfn_launcher.py \
    --state-machine-arn arn:... \
    --state-bucket acme-lz-terraform-state \
    --from-dynamodb \
    --inventory-table lz-account-inventory \
    --plan-only \
    --wait
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
import uuid
from pathlib import Path
from typing import Optional

import boto3

logging.basicConfig(
    format="%(asctime)s %(levelname)-8s %(message)s",
    level=logging.INFO,
    datefmt="%H:%M:%S",
)
log = logging.getLogger("sfn_launcher")


# ---------------------------------------------------------------------------
# Account discovery helpers
# ---------------------------------------------------------------------------

def _discover_from_dynamodb(table_name: str, region: str) -> list[dict]:
    """Return all accounts with status=provisioned from lz-account-inventory."""
    ddb = boto3.resource("dynamodb", region_name=region)
    table = ddb.Table(table_name)

    items: list[dict] = []
    kwargs: dict = {
        "IndexName": "status-index",
        "KeyConditionExpression": "status = :s",
        "ExpressionAttributeValues": {":s": "provisioned"},
        "ProjectionExpression": "account_id, account_name, environment, ou",
    }

    while True:
        resp = table.query(**kwargs)
        items.extend(resp.get("Items", []))
        lek = resp.get("LastEvaluatedKey")
        if not lek:
            break
        kwargs["ExclusiveStartKey"] = lek

    log.info("DynamoDB discovered %d provisioned accounts", len(items))
    return items


def _discover_from_manifest(account_ids_file: Optional[Path]) -> list[dict]:
    """
    Parse a newline-separated file of 'account_id,account_name' pairs.

    Lines starting with # are ignored.
    """
    if not account_ids_file or not account_ids_file.exists():
        return []

    accounts = []
    for raw in account_ids_file.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(",", 1)
        if len(parts) != 2:
            log.warning("Skipping malformed line: %r", line)
            continue
        accounts.append({"account_id": parts[0].strip(), "account_name": parts[1].strip()})
    return accounts


def _build_items(
    accounts: list[dict],
    environment: str,
    plan_only: bool,
) -> list[dict]:
    """Normalise account dicts and inject run-time fields."""
    items = []
    for acc in accounts:
        items.append({
            "account_id":   str(acc.get("account_id", acc.get("id", ""))),
            "account_name": str(acc.get("account_name", acc.get("name", ""))),
            "environment":  str(acc.get("environment", environment)),
            "ou":           str(acc.get("ou", "")),
            "plan_only":    "true" if plan_only else "false",
        })
    return items


# ---------------------------------------------------------------------------
# S3 helpers
# ---------------------------------------------------------------------------

def _upload_policy_map(
    s3: "boto3.client",
    bucket: str,
    local_path: Path,
    s3_key: str,
) -> None:
    """Upload account_policy_map.yaml to S3 so Fargate tasks can fetch it."""
    if not local_path.exists():
        log.warning("Policy map not found at %s — skipping upload", local_path)
        return
    s3.upload_file(
        Filename=str(local_path),
        Bucket=bucket,
        Key=s3_key,
    )
    log.info("Uploaded policy map → s3://%s/%s", bucket, s3_key)


def _upload_job_manifest(
    s3: "boto3.client",
    bucket: str,
    run_id: str,
    accounts: list[dict],
) -> str:
    """Upload the job manifest JSON to S3 and return its S3 key."""
    key = f"sfn-jobs/{run_id}.json"
    payload = json.dumps({"accounts": accounts}, indent=2)
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=payload.encode(),
        ContentType="application/json",
    )
    log.info(
        "Uploaded manifest: %d accounts → s3://%s/%s",
        len(accounts),
        bucket,
        key,
    )
    return key


# ---------------------------------------------------------------------------
# Step Functions helpers
# ---------------------------------------------------------------------------

def _start_execution(
    sfn: "boto3.client",
    state_machine_arn: str,
    run_id: str,
    manifest_key: str,
) -> str:
    """Start the SFN execution and return the execution ARN."""
    resp = sfn.start_execution(
        stateMachineArn=state_machine_arn,
        name=run_id,
        input=json.dumps({"job_manifest_key": manifest_key}),
    )
    arn = resp["executionArn"]
    log.info("Started execution: %s", arn)
    return arn


_TERMINAL_STATUSES = {"SUCCEEDED", "FAILED", "TIMED_OUT", "ABORTED"}


def _wait_for_execution(
    sfn: "boto3.client",
    execution_arn: str,
    poll_interval: int = 15,
) -> str:
    """
    Poll until the execution reaches a terminal status.

    Returns the final status string.
    """
    log.info("Waiting for execution to complete (polling every %ds) …", poll_interval)
    start = time.monotonic()

    while True:
        resp = sfn.describe_execution(executionArn=execution_arn)
        status = resp["status"]
        elapsed = int(time.monotonic() - start)

        if status in _TERMINAL_STATUSES:
            log.info("Execution %s after %ds", status, elapsed)
            return status

        log.info("Status: %s (%ds elapsed) …", status, elapsed)
        time.sleep(poll_interval)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Launch SFN account-provisioning pipeline",
        formatter_class=argparse.RawTextHelpFormatter,
    )

    # Target
    p.add_argument("--state-machine-arn", required=True,
                   help="ARN of the lz-account-pipeline state machine")
    p.add_argument("--state-bucket", required=True,
                   help="S3 bucket for job manifests and TF state")
    p.add_argument("--region", default=None,
                   help="AWS region (default: boto3 session default)")

    # Account sources (mutually exclusive; at least one required)
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--account-id", nargs="+", dest="account_ids",
                     help="One or more account IDs (requires --account-name for single account)")
    src.add_argument("--account-ids-file", type=Path,
                     help="File with 'account_id,account_name' lines")
    src.add_argument("--from-dynamodb", action="store_true",
                     help="Discover provisioned accounts from DynamoDB inventory table")

    # Account name (only for --account-id with single account)
    p.add_argument("--account-name", default=None,
                   help="Account name for --account-id with a single account")

    # DynamoDB options
    p.add_argument("--inventory-table", default="lz-account-inventory",
                   help="DynamoDB table for --from-dynamodb (default: lz-account-inventory)")

    # Run options
    p.add_argument("--environment", default="auto",
                   help="Override environment for all accounts")
    p.add_argument("--plan-only", action="store_true",
                   help="Set PLAN_ONLY=true on all Fargate tasks (drift check mode)")
    p.add_argument("--policy-map-local", type=Path, default=Path("account_policy_map.yaml"),
                   help="Local path to account_policy_map.yaml to upload to S3")
    p.add_argument("--policy-map-s3-key", default="config/account_policy_map.yaml",
                   help="S3 key for the policy map (default: config/account_policy_map.yaml)")
    p.add_argument("--wait", action="store_true",
                   help="Block until the SFN execution completes and exit non-zero on failure")

    return p


def main() -> int:
    args = _build_parser().parse_args()

    # Build account list
    region = args.region or boto3.session.Session().region_name or "us-east-1"
    sfn = boto3.client("stepfunctions", region_name=region)
    s3  = boto3.client("s3",            region_name=region)

    if args.from_dynamodb:
        raw_accounts = _discover_from_dynamodb(args.inventory_table, region)
    elif args.account_ids_file:
        raw_accounts = _discover_from_manifest(args.account_ids_file)
    else:
        # --account-id list
        if len(args.account_ids) == 1 and not args.account_name:
            log.error("--account-name is required when --account-id has a single value")
            return 1
        if len(args.account_ids) > 1 and args.account_name:
            log.warning(
                "--account-name is ignored when multiple --account-id values are provided"
            )
        if len(args.account_ids) == 1:
            raw_accounts = [
                {"account_id": args.account_ids[0], "account_name": args.account_name}
            ]
        else:
            # Multiple IDs without names — names default to IDs
            raw_accounts = [
                {"account_id": aid, "account_name": aid} for aid in args.account_ids
            ]

    if not raw_accounts:
        log.error("No accounts found — nothing to do")
        return 1

    accounts = _build_items(raw_accounts, args.environment, args.plan_only)
    log.info(
        "Launching %d accounts | plan_only=%s | env=%s",
        len(accounts),
        args.plan_only,
        args.environment,
    )

    # Upload policy map so Fargate tasks can fetch it
    _upload_policy_map(s3, args.state_bucket, args.policy_map_local, args.policy_map_s3_key)

    # Upload job manifest
    run_id = f"lz-run-{uuid.uuid4().hex[:12]}"
    manifest_key = _upload_job_manifest(s3, args.state_bucket, run_id, accounts)

    # Start execution
    execution_arn = _start_execution(sfn, args.state_machine_arn, run_id, manifest_key)
    print(f"EXECUTION_ARN={execution_arn}", flush=True)

    if not args.wait:
        return 0

    # Wait and propagate failure
    status = _wait_for_execution(sfn, execution_arn)
    if status != "SUCCEEDED":
        log.error("Pipeline did not SUCCEED (status=%s)", status)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
