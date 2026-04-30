#!/usr/bin/env python3
"""
deploy_accounts.py — fleet orchestrator for the account-setup stack.

Replaces the GitHub Actions matrix sweep with a single-runner Python
orchestrator that scales past the 256-job matrix cap and runs many
accounts concurrently via a ThreadPoolExecutor. Designed for 10k+ account
estates.

Why a script vs matrix:
  * No 256-job ceiling
  * One runner setup cost (vs N runner provisions)
  * Dynamic concurrency tuning at runtime (no re-trigger to change)
  * Adaptive retry on throttle errors with central state
  * Single aggregated JSON report

Per account it runs:
    1. resolve_account.py  -> generates terraform.tfvars
    2. terraform init      -> per-account state key
    3. terraform plan      -> -detailed-exitcode
    4. terraform apply     -> only if plan shows changes and not --plan-only

Concurrency model:
    * ThreadPoolExecutor with --max-parallel workers (default 50)
    * Each worker uses an isolated TF_DATA_DIR + tfvars copy under
      .deploy_workdir/<account_id>/ to prevent races on shared stack files
    * Per-account log written to logs/<account_id>.log (streamed live)

Retry model:
    * Transient AWS errors (Throttling, RequestLimitExceeded, 5xx, 429)
      retried up to 3 times with exponential backoff (2^n * 10s)
    * terraform exit codes other than 0/2 from plan are treated as failures

Exit code:
    0 if every targeted account succeeded (or had no changes)
    1 if at least one account failed (full report in deploy-report.json)

Usage:
    # Sweep all provisioned accounts (drift remediation)
    python3 scripts/deploy_accounts.py --all

    # Plan-only (no apply) — safe to run anytime
    python3 scripts/deploy_accounts.py --all --plan-only

    # Subset by OU
    python3 scripts/deploy_accounts.py --ou Production --max-parallel 20

    # Specific accounts
    python3 scripts/deploy_accounts.py --account-id 111111111111 222222222222

    # Debug: serial execution + verbose
    python3 scripts/deploy_accounts.py --all --max-parallel 1 --verbose
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parent.parent
# ACCOUNTS_DIR and RESOLVE_SCRIPT can be overridden via env vars so that the
# drift-sweep workflow (which only checks out aws-lz-platform) can point at
# the separately-checked-out aws-lz-accounts directory.
ACCOUNTS_DIR = Path(os.environ.get("LZ_ACCOUNTS_DIR", str(REPO_ROOT / "accounts")))
RESOLVE_SCRIPT = Path(os.environ.get("LZ_RESOLVE_SCRIPT", str(REPO_ROOT / "scripts" / "resolve_account.py")))
STACK_DIR = REPO_ROOT / "stacks" / "account-setup"
WORK_ROOT = REPO_ROOT / ".deploy_workdir"
LOG_DIR = REPO_ROOT / "logs"
REPORT_FILE = REPO_ROOT / "deploy-report.json"

ACCOUNT_ID_RE = re.compile(r"^\d{12}$")

THROTTLE_PATTERNS = (
    "Throttling",
    "ThrottlingException",
    "RequestLimitExceeded",
    "TooManyRequestsException",
    "RateExceeded",
    "Rate exceeded",
    "ServiceUnavailable",
    "InternalServerError",
    "(429)",
    "(503)",
    "(500)",
)

# ── Graceful shutdown (SIGTERM / Ctrl-C) ─────────────────────────────────────
# GitHub Actions sends SIGTERM before killing the process. We catch it so
# in-flight Terraform processes can finish their current command rather than
# getting killed mid-apply, which would corrupt state.
_SHUTDOWN = threading.Event()


def _handle_signal(signum: int, frame: object) -> None:  # noqa: ARG001
    print(
        f"\n[signal {signum}] Graceful shutdown requested — "
        "finishing in-flight accounts, not starting new ones.",
        file=sys.stderr,
    )
    _SHUTDOWN.set()


signal.signal(signal.SIGTERM, _handle_signal)
signal.signal(signal.SIGINT, _handle_signal)

# ── AWS API rate-limiter ─────────────────────────────────────────────────────
# Prevents Organizations / IAM from throttling when 100+ workers fire
# DescribeAccount / AssumeRole simultaneously. Caps concurrent AWS API
# calls across all worker threads. Terraform itself also honours
# max_retries=25 in providers.tf, but this is a belt-and-suspenders guard.
_AWS_SEMAPHORE = threading.Semaphore(30)  # max 30 concurrent AWS API calls


class RunStateTable:
    """DynamoDB-backed run state for resume-on-failure.

    Writes each account result to DynamoDB as it completes. On --resume,
    loads completed accounts from a prior run so they are skipped.
    Degrades gracefully if boto3 is unavailable or the table doesn't exist.

    Table schema: PK=run_id (S), SK=account_id (S), TTL=14 days.
    Create the table via stacks/00-bootstrap (aws_dynamodb_table.deploy_run_state).
    """

    DEFAULT_TABLE = os.environ.get("DEPLOY_RUN_STATE_TABLE", "acme-lz-deploy-run-state")
    TTL_DAYS = 14

    def __init__(self, run_id: str, region: str, table_name: str, enabled: bool = True):
        self.run_id = run_id
        self._table = None
        if not enabled:
            return
        try:
            import boto3  # noqa: PLC0415
            ddb = boto3.resource("dynamodb", region_name=region)
            self._table = ddb.Table(table_name)
        except Exception as exc:
            print(
                f"warning: DynamoDB run state unavailable ({exc}); "
                "running without resume support",
                file=sys.stderr,
            )

    @property
    def available(self) -> bool:
        return self._table is not None

    def load_completed(self) -> set[str]:
        """Return account_ids that already succeeded in this run (for --resume)."""
        if not self._table:
            return set()
        completed: set[str] = set()
        try:
            from boto3.dynamodb.conditions import Key  # noqa: PLC0415

            kwargs: dict = {"KeyConditionExpression": Key("run_id").eq(self.run_id)}
            while True:
                resp = self._table.query(**kwargs)
                for item in resp.get("Items", []):
                    if item.get("status") in ("applied", "clean"):
                        completed.add(str(item["account_id"]))
                if "LastEvaluatedKey" not in resp:
                    break
                kwargs["ExclusiveStartKey"] = resp["LastEvaluatedKey"]
        except Exception as exc:
            print(
                f"warning: could not load run state from DynamoDB: {exc}",
                file=sys.stderr,
            )
        return completed

    def record(self, result: AccountResult) -> None:
        """Write account result to DynamoDB (best-effort, never raises)."""
        if not self._table:
            return
        try:
            self._table.put_item(
                Item={
                    "run_id": self.run_id,
                    "account_id": result.account_id,
                    "account_name": result.account_name,
                    "status": result.status,
                    "duration_s": str(round(result.duration_s, 2)),
                    "attempts": result.attempts,
                    "error": result.error or "",
                    "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "ttl": int(time.time()) + self.TTL_DAYS * 86400,
                }
            )
        except Exception as exc:
            print(
                f"warning: could not write run state to DynamoDB: {exc}",
                file=sys.stderr,
            )


@dataclass
class AccountTask:
    account_id: str
    account_name: str
    environment: str = "auto"
    ou: str = ""


@dataclass
class AccountResult:
    account_id: str
    account_name: str
    status: str  # "clean" | "applied" | "planned" | "failed" | "skipped"
    duration_s: float = 0.0
    attempts: int = 1
    error: str | None = None
    log_path: str = ""

    def is_failure(self) -> bool:
        return self.status == "failed"


def _validate_account_id(account_id: str) -> str:
    if not ACCOUNT_ID_RE.match(account_id):
        raise ValueError(f"invalid account_id: {account_id!r}")
    return account_id


def discover_accounts(
    *,
    account_ids: list[str] | None,
    ou_filter: str | None,
    env_filter: str | None,
    name_pattern: str | None,
    all_accounts: bool,
) -> list[AccountTask]:
    """Build the work list from accounts/<id>/account.json metadata."""
    if not ACCOUNTS_DIR.is_dir() and not account_ids:
        return []

    explicit_ids = {_validate_account_id(a) for a in (account_ids or [])}
    name_re = re.compile(name_pattern) if name_pattern else None
    tasks: list[AccountTask] = []

    for child in sorted(ACCOUNTS_DIR.iterdir() if ACCOUNTS_DIR.is_dir() else []):
        if not child.is_dir() or child.name.startswith("_"):
            continue
        meta_path = child / "account.json"
        if not meta_path.is_file():
            continue
        try:
            meta = json.loads(meta_path.read_text())
        except (OSError, json.JSONDecodeError) as e:
            print(f"warning: cannot read {meta_path}: {e}", file=sys.stderr)
            continue

        account_id = str(meta.get("account_id", ""))
        if not ACCOUNT_ID_RE.match(account_id):
            continue

        if explicit_ids and account_id not in explicit_ids:
            continue
        if not all_accounts and not explicit_ids:
            # Without --all or explicit IDs, require at least one filter
            if not (ou_filter or env_filter or name_pattern):
                continue
        if meta.get("status") and meta["status"] != "provisioned":
            continue
        if ou_filter and meta.get("ou") != ou_filter:
            continue
        if env_filter and meta.get("environment") != env_filter:
            continue
        account_name = str(meta.get("account_name", ""))
        if name_re and not name_re.search(account_name):
            continue

        tasks.append(
            AccountTask(
                account_id=account_id,
                account_name=account_name,
                environment=str(meta.get("environment", "auto")),
                ou=str(meta.get("ou", "")),
            )
        )

    # Honour --account-id even for accounts without local metadata
    discovered_ids = {t.account_id for t in tasks}
    for missing in sorted(explicit_ids - discovered_ids):
        tasks.append(AccountTask(account_id=missing, account_name=missing))

    return tasks


def discover_from_dynamodb(
    *,
    table_name: str,
    region: str,
    account_ids: list[str] | None = None,
    ou_filter: str | None = None,
    env_filter: str | None = None,
    name_pattern: str | None = None,
) -> list[AccountTask]:
    """Discover provisioned accounts from the lz-account-inventory DynamoDB table.

    Preferred over account.json scanning at scale: a single paginated Scan/Query
    fetches thousands of records in <1s with no filesystem traversal cost.

    Table schema (managed by stacks/sfn-pipeline or stacks/00-bootstrap):
      PK: account_id (S)
      GSI1: environment-index  PK=environment
      GSI2: ou-index           PK=ou
      Attributes: account_name, environment, ou, status, provisioned_at
    """
    try:
        import boto3  # noqa: PLC0415
    except ImportError:
        print("warning: boto3 not available — falling back to account.json discovery", file=sys.stderr)
        return []

    ddb = boto3.resource("dynamodb", region_name=region)
    table = ddb.Table(table_name)
    name_re = re.compile(name_pattern) if name_pattern else None
    explicit_ids = set(account_ids or [])

    items: list[dict] = []
    try:
        # Use GSI when filtering by environment or OU to avoid full scan
        if env_filter and not ou_filter:
            kwargs: dict = {
                "IndexName": "environment-index",
                "KeyConditionExpression": "environment = :env",
                "ExpressionAttributeValues": {":env": env_filter},
                "FilterExpression": "#s = :prov",
                "ExpressionAttributeNames": {"#s": "status"},
            }
            kwargs["ExpressionAttributeValues"][":prov"] = "provisioned"
            while True:
                resp = table.query(**kwargs)
                items.extend(resp.get("Items", []))
                if "LastEvaluatedKey" not in resp:
                    break
                kwargs["ExclusiveStartKey"] = resp["LastEvaluatedKey"]
        else:
            # Full scan — still fast for <10k items with DynamoDB
            scan_kwargs: dict = {
                "FilterExpression": "#s = :prov",
                "ExpressionAttributeNames": {"#s": "status"},
                "ExpressionAttributeValues": {":prov": "provisioned"},
            }
            while True:
                resp = table.scan(**scan_kwargs)
                items.extend(resp.get("Items", []))
                if "LastEvaluatedKey" not in resp:
                    break
                scan_kwargs["ExclusiveStartKey"] = resp["LastEvaluatedKey"]
    except Exception as exc:
        print(f"warning: DynamoDB scan failed ({exc}) — falling back to account.json discovery", file=sys.stderr)
        return []

    tasks: list[AccountTask] = []
    for item in items:
        aid = str(item.get("account_id", ""))
        if not ACCOUNT_ID_RE.match(aid):
            continue
        if explicit_ids and aid not in explicit_ids:
            continue
        if ou_filter and item.get("ou") != ou_filter:
            continue
        aname = str(item.get("account_name", ""))
        if name_re and not name_re.search(aname):
            continue
        tasks.append(
            AccountTask(
                account_id=aid,
                account_name=aname,
                environment=str(item.get("environment", "auto")),
                ou=str(item.get("ou", "")),
            )
        )

    print(f"DynamoDB inventory: discovered {len(tasks)} provisioned accounts from '{table_name}'")
    return tasks


def chunk_tasks(tasks: list[AccountTask], chunk_size: int) -> list[list[AccountTask]]:
    """Split task list into equal-sized chunks for staged parallel execution.

    Processing accounts in chunks prevents a single 7GB GitHub Actions runner
    from being overwhelmed when running 100+ parallel Terraform processes.
    Each chunk runs to completion before the next starts, so the runner's
    .deploy_workdir/ never holds more than chunk_size workdirs simultaneously.

    Recommended chunk_size = max_parallel (e.g. both = 10 → 10 workers × 10 chunks
    for 100 accounts instead of 100 workers at once).
    """
    if chunk_size <= 0 or chunk_size >= len(tasks):
        return [tasks]
    return [tasks[i: i + chunk_size] for i in range(0, len(tasks), chunk_size)]


def _is_transient(stderr: str) -> bool:
    return any(p in stderr for p in THROTTLE_PATTERNS)


def _run(cmd: list[str], cwd: Path, env: dict[str, str], log_fp) -> int:
    """Run a subprocess, streaming combined output to log_fp. Return rc."""
    log_fp.write(f"\n$ {' '.join(cmd)}\n")
    log_fp.flush()
    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert proc.stdout is not None
    for line in proc.stdout:
        log_fp.write(line)
    proc.wait()
    return proc.returncode


def _prepare_workdir(task: AccountTask) -> Path:
    """Create per-account isolated workdir mirroring the stack's .tf files."""
    work = WORK_ROOT / task.account_id
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    # Symlink/copy *.tf so each worker has its own .terraform/ dir
    for tf in STACK_DIR.glob("*.tf"):
        (work / tf.name).write_text(tf.read_text())
    return work


def _read_log_tail(log_path: Path, n: int = 30) -> str:
    try:
        with log_path.open() as fp:
            lines = fp.readlines()
        return "".join(lines[-n:])
    except OSError:
        return ""


def _write_account_meta(task: AccountTask) -> None:
    """Persist account.json in ACCOUNTS_DIR after a successful apply.

    This file is the source of truth for discover_accounts() used by the
    drift sweep (--all flag). Without it, provisioned accounts are invisible
    to the sweep.
    """
    meta_dir = ACCOUNTS_DIR / task.account_id
    try:
        meta_dir.mkdir(parents=True, exist_ok=True)
        (meta_dir / "account.json").write_text(
            json.dumps(
                {
                    "account_id": task.account_id,
                    "account_name": task.account_name,
                    "environment": task.environment,
                    "ou": task.ou,
                    "status": "provisioned",
                    "provisioned_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                },
                indent=2,
            )
            + "\n"
        )
    except OSError as e:
        print(f"warning: could not write account.json for {task.account_id}: {e}", file=sys.stderr)


def deploy_one(
    task: AccountTask,
    *,
    plan_only: bool,
    state_bucket: str,
    region: str,
    max_attempts: int,
    verbose: bool,
    run_state: RunStateTable | None = None,
) -> AccountResult:
    LOG_DIR.mkdir(exist_ok=True)
    log_path = LOG_DIR / f"{task.account_id}.log"
    started = time.time()

    for attempt in range(1, max_attempts + 1):
        # Honour graceful shutdown: don't start a new attempt after signal received
        if _SHUTDOWN.is_set():
            return AccountResult(
                task.account_id, task.account_name, "failed",
                duration_s=time.time() - started, attempts=attempt,
                error="interrupted by shutdown signal", log_path=str(log_path),
            )

        try:
            work = _prepare_workdir(task)
        except OSError as e:
            return AccountResult(
                task.account_id, task.account_name, "failed",
                error=f"workdir prep failed: {e}",
                log_path=str(log_path),
            )

        env = {
            **os.environ,
            "TF_INPUT": "0",
            "TF_IN_AUTOMATION": "1",
            "AWS_REGION": region,
            "AWS_DEFAULT_REGION": region,
            # Share provider binaries across parallel workers — cuts init time
            # from ~60s/worker to ~5s after first download.
            "TF_PLUGIN_CACHE_DIR": "/tmp/tf-plugin-cache",
            "TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE": "1",
        }

        with log_path.open("a") as log_fp:
            log_fp.write(f"\n===== attempt {attempt}/{max_attempts} =====\n")

            # 1. Generate tfvars (writes into stack dir; we then copy to workdir)
            rc = _run(
                ["python3", str(RESOLVE_SCRIPT),
                 task.account_id, task.account_name],
                cwd=RESOLVE_SCRIPT.parent.parent, env=env, log_fp=log_fp,
            )
            if rc != 0:
                if verbose:
                    print(f"[{task.account_id}] resolve failed rc={rc}", file=sys.stderr)
                return AccountResult(
                    task.account_id, task.account_name, "failed",
                    duration_s=time.time() - started, attempts=attempt,
                    error="resolve_account.py failed", log_path=str(log_path),
                )
            tfvars_src = STACK_DIR / "terraform.tfvars"
            if not tfvars_src.exists():
                return AccountResult(
                    task.account_id, task.account_name, "failed",
                    duration_s=time.time() - started, attempts=attempt,
                    error="terraform.tfvars not produced", log_path=str(log_path),
                )
            shutil.copy2(tfvars_src, work / "terraform.tfvars")

            # 2. terraform init (per-account state key)
            # _AWS_SEMAPHORE caps simultaneous inits to prevent S3/DynamoDB
            # throttle when 100+ workers all run init at the same moment.
            init_cmd = [
                "terraform", "init", "-input=false", "-no-color",
                f"-backend-config=bucket={state_bucket}",
                f"-backend-config=key=account-setup/{task.account_id}/terraform.tfstate",
                f"-backend-config=region={region}",
            ]
            with _AWS_SEMAPHORE:
                rc = _run(init_cmd, cwd=work, env=env, log_fp=log_fp)
            if rc != 0:
                tail = _read_log_tail(log_path)
                if attempt < max_attempts and _is_transient(tail):
                    backoff = (2 ** attempt) * 10
                    log_fp.write(f"\n-- transient init failure, sleeping {backoff}s --\n")
                    time.sleep(backoff)
                    continue
                result = AccountResult(
                    task.account_id, task.account_name, "failed",
                    duration_s=time.time() - started, attempts=attempt,
                    error="terraform init failed", log_path=str(log_path),
                )
                if run_state:
                    run_state.record(result)
                return result

            # 3. terraform plan -detailed-exitcode (0=clean, 2=changes, other=err)
            plan_cmd = [
                "terraform", "plan", "-input=false", "-no-color",
                "-detailed-exitcode",
                "-var-file=terraform.tfvars",
                "-out=tfplan",
            ]
            rc = _run(plan_cmd, cwd=work, env=env, log_fp=log_fp)
            if rc == 0:
                result = AccountResult(
                    task.account_id, task.account_name, "clean",
                    duration_s=time.time() - started, attempts=attempt,
                    log_path=str(log_path),
                )
                if run_state:
                    run_state.record(result)
                return result
            if rc != 2:
                tail = _read_log_tail(log_path)
                if attempt < max_attempts and _is_transient(tail):
                    backoff = (2 ** attempt) * 10
                    log_fp.write(f"\n-- transient plan failure, sleeping {backoff}s --\n")
                    time.sleep(backoff)
                    continue
                result = AccountResult(
                    task.account_id, task.account_name, "failed",
                    duration_s=time.time() - started, attempts=attempt,
                    error=f"terraform plan exit={rc}", log_path=str(log_path),
                )
                if run_state:
                    run_state.record(result)
                return result

            # 4. apply (or stop here if plan-only)
            if plan_only:
                result = AccountResult(
                    task.account_id, task.account_name, "planned",
                    duration_s=time.time() - started, attempts=attempt,
                    log_path=str(log_path),
                )
                if run_state:
                    run_state.record(result)
                return result

            apply_cmd = ["terraform", "apply", "-input=false", "-no-color", "-auto-approve", "tfplan"]
            rc = _run(apply_cmd, cwd=work, env=env, log_fp=log_fp)
            if rc != 0:
                tail = _read_log_tail(log_path)
                if attempt < max_attempts and _is_transient(tail):
                    backoff = (2 ** attempt) * 10
                    log_fp.write(f"\n-- transient apply failure, sleeping {backoff}s --\n")
                    time.sleep(backoff)
                    continue
                result = AccountResult(
                    task.account_id, task.account_name, "failed",
                    duration_s=time.time() - started, attempts=attempt,
                    error=f"terraform apply exit={rc}", log_path=str(log_path),
                )
                if run_state:
                    run_state.record(result)
                return result

            result = AccountResult(
                task.account_id, task.account_name, "applied",
                duration_s=time.time() - started, attempts=attempt,
                log_path=str(log_path),
            )
            if run_state:
                run_state.record(result)

            # Write account metadata so discover_accounts() can find it on drift sweeps
            _write_account_meta(task)

            return result

    result = AccountResult(
        task.account_id, task.account_name, "failed",
        duration_s=time.time() - started, attempts=max_attempts,
        error="exhausted retries", log_path=str(log_path),
    )
    if run_state:
        run_state.record(result)
    return result


def run_fleet(
    tasks: list[AccountTask],
    *,
    plan_only: bool,
    max_parallel: int,
    chunk_size: int,
    state_bucket: str,
    region: str,
    max_attempts: int,
    verbose: bool,
    run_state: RunStateTable | None = None,
    resume: bool = False,
) -> list[AccountResult]:
    if not tasks:
        return []
    LOG_DIR.mkdir(exist_ok=True)
    WORK_ROOT.mkdir(exist_ok=True)
    Path("/tmp/tf-plugin-cache").mkdir(parents=True, exist_ok=True)
    results: list[AccountResult] = []

    # Resume: skip accounts that already succeeded in a prior run
    if resume and run_state:
        completed_ids = run_state.load_completed()
        if completed_ids:
            skipped = [t for t in tasks if t.account_id in completed_ids]
            tasks = [t for t in tasks if t.account_id not in completed_ids]
            print(f"Resume: skipping {len(skipped)} already-completed accounts "
                  f"({', '.join(s.account_id for s in skipped[:5])}"
                  f"{'...' if len(skipped) > 5 else ''})")
            for s in skipped:
                results.append(
                    AccountResult(s.account_id, s.account_name, "skipped")
                )
        else:
            print("Resume: no previously completed accounts found for this run_id")

    chunks = chunk_tasks(tasks, chunk_size)
    total = len(tasks)
    total_chunks = len(chunks)
    done = len(results)  # already-skipped count

    print(f"Deploying {total} accounts | chunks={total_chunks} | "
          f"max_parallel={max_parallel} | plan_only={plan_only} | retries={max_attempts}")
    if total_chunks > 1:
        print(f"  Chunked into {total_chunks} batches of \u2264{chunk_size} "
              "(prevents runner OOM on 100+ account estates)")

    fleet_started = time.time()

    for chunk_idx, chunk in enumerate(chunks, 1):
        if _SHUTDOWN.is_set():
            print(f"Shutdown signal received: skipping remaining {total - done} accounts.")
            break

        if total_chunks > 1:
            print(f"\n\u2500\u2500 Chunk {chunk_idx}/{total_chunks} ({len(chunk)} accounts) \u2500\u2500")

        with ThreadPoolExecutor(max_workers=min(max_parallel, len(chunk))) as pool:
            futures = {
                pool.submit(
                    deploy_one, t,
                    plan_only=plan_only, state_bucket=state_bucket,
                    region=region, max_attempts=max_attempts, verbose=verbose,
                    run_state=run_state,
                ): t for t in chunk
            }
            for fut in as_completed(futures):
                res = fut.result()
                results.append(res)
                done += 1
                mark = {"clean": "\u00b7", "planned": "P", "applied": "\u2713",
                        "failed": "\u2717", "skipped": "-"}.get(res.status, "?")
                # ETA estimation
                elapsed = time.time() - fleet_started
                rate = done / elapsed if elapsed > 0 else 0
                remaining = total - done
                eta_s = int(remaining / rate) if rate > 0 and remaining > 0 else 0
                eta_str = f" ETA \u2248{eta_s // 60}m{eta_s % 60:02d}s" if eta_s > 0 else ""
                print(f"  [{done}/{total}] {mark} {res.account_id} "
                      f"{res.account_name} ({res.status}, {res.duration_s:.1f}s){eta_str}")
    return results


def write_report(results: list[AccountResult]) -> dict:
    summary = {
        "total": len(results),
        "applied": sum(1 for r in results if r.status == "applied"),
        "planned": sum(1 for r in results if r.status == "planned"),
        "clean": sum(1 for r in results if r.status == "clean"),
        "failed": sum(1 for r in results if r.status == "failed"),
        "results": [asdict(r) for r in results],
    }
    REPORT_FILE.write_text(json.dumps(summary, indent=2))
    return summary


def write_gha_summary(summary: dict) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    lines = [
        "## Account Deployment Summary",
        "",
        f"- Total: **{summary['total']}**",
        f"- Applied: **{summary['applied']}**",
        f"- Plan-only: **{summary['planned']}**",
        f"- Clean (no changes): **{summary['clean']}**",
        f"- Failed: **{summary['failed']}**",
        "",
    ]
    failed = [r for r in summary["results"] if r["status"] == "failed"]
    if failed:
        lines += ["### Failures", "", "| Account ID | Name | Attempts | Error |", "|---|---|---|---|"]
        for r in failed:
            lines.append(f"| `{r['account_id']}` | {r['account_name']} | {r['attempts']} | {r['error'] or ''} |")
        lines.append("")
    Path(summary_path).write_text("\n".join(lines))


def main(argv: Iterable[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Parallel account-setup deployer (replaces matrix workflow).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--account-id", nargs="*", default=[], help="Specific 12-digit account IDs.")
    p.add_argument("--ou", default=None, help="Filter by OU (e.g. Production).")
    p.add_argument("--env", dest="env_filter", default=None,
                   choices=["production", "staging", "development", "sandbox"])
    p.add_argument("--name-pattern", default=None, help="Regex on account_name.")
    p.add_argument("--all", action="store_true", help="Sweep every provisioned account.")
    p.add_argument("--plan-only", action="store_true", help="Plan but do not apply.")
    p.add_argument("--max-parallel", type=int, default=10, help="Concurrent terraform workers (default 10).")
    p.add_argument("--max-attempts", type=int, default=3, help="Retries on transient failures.")
    p.add_argument("--state-bucket", default=os.environ.get("TF_STATE_BUCKET", "acme-lz-terraform-state"))
    p.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    p.add_argument("--verbose", action="store_true")
    # ── Run state / resume ──────────────────────────────────────────────────
    p.add_argument(
        "--run-id",
        default=None,
        help="Stable UUID for this run (auto-generated if not set). "
             "Pass the same value with --resume to continue a failed batch.",
    )
    p.add_argument(
        "--resume",
        action="store_true",
        help="Skip accounts that already succeeded in a prior run identified by --run-id.",
    )
    p.add_argument(
        "--state-table",
        default=RunStateTable.DEFAULT_TABLE,
        help=f"DynamoDB table for run state (default: {RunStateTable.DEFAULT_TABLE}).",
    )
    p.add_argument(
        "--no-state",
        action="store_true",
        help="Disable DynamoDB run state tracking entirely.",
    )
    # ── Scale controls ──────────────────────────────────────────────────────
    p.add_argument(
        "--chunk-size",
        type=int,
        default=int(os.environ.get("LZ_CHUNK_SIZE", "0")),
        help="Process accounts in chunks of this size to cap runner memory usage. "
             "0 = no chunking (single batch). Recommended: equal to --max-parallel "
             "so each chunk fully saturates the worker pool before the next starts. "
             "Example: --max-parallel 10 --chunk-size 10 for 100-account estates.",
    )
    # ── DynamoDB inventory source ───────────────────────────────────────────
    p.add_argument(
        "--from-dynamodb",
        action="store_true",
        help="Discover accounts from lz-account-inventory DynamoDB table instead "
             "of scanning account.json files. Faster and more reliable at scale.",
    )
    p.add_argument(
        "--inventory-table",
        default=os.environ.get("LZ_INVENTORY_TABLE", "lz-account-inventory"),
        help="DynamoDB table name for account inventory (default: lz-account-inventory).",
    )
    args = p.parse_args(list(argv) if argv is not None else None)

    if args.max_parallel < 1:
        print("--max-parallel must be >= 1", file=sys.stderr)
        return 2

    if args.resume and not args.run_id:
        print("--resume requires --run-id", file=sys.stderr)
        return 2

    # chunk_size=0 means no chunking (process all in one ThreadPoolExecutor batch)
    chunk_size = args.chunk_size if args.chunk_size > 0 else max(len([]), args.max_parallel)

    run_id = args.run_id or str(uuid.uuid4())
    run_state = RunStateTable(
        run_id=run_id,
        region=args.region,
        table_name=args.state_table,
        enabled=not args.no_state,
    )
    print(f"Run ID: {run_id}")

    # ── Discover accounts ───────────────────────────────────────────────────
    if args.from_dynamodb:
        tasks = discover_from_dynamodb(
            table_name=args.inventory_table,
            region=args.region,
            account_ids=args.account_id or None,
            ou_filter=args.ou,
            env_filter=args.env_filter,
            name_pattern=args.name_pattern,
        )
        if not tasks and args.account_id:
            # Fallback: explicit IDs always work even without inventory record
            tasks = [AccountTask(account_id=a, account_name=a) for a in args.account_id]
    else:
        tasks = discover_accounts(
            account_ids=args.account_id or None,
            ou_filter=args.ou,
            env_filter=args.env_filter,
            name_pattern=args.name_pattern,
            all_accounts=args.all,
        )

    if not tasks:
        print("No accounts matched filters.", file=sys.stderr)
        return 0

    # Auto-set chunk_size to max_parallel when chunking wasn't explicitly set
    effective_chunk_size = args.chunk_size if args.chunk_size > 0 else len(tasks)

    results = run_fleet(
        tasks,
        plan_only=args.plan_only,
        max_parallel=args.max_parallel,
        chunk_size=effective_chunk_size,
        state_bucket=args.state_bucket,
        region=args.region,
        max_attempts=args.max_attempts,
        verbose=args.verbose,
        run_state=run_state,
        resume=args.resume,
    )
    summary = write_report(results)
    summary["run_id"] = run_id
    REPORT_FILE.write_text(json.dumps(summary, indent=2))
    write_gha_summary(summary)

    print(f"\nReport: {REPORT_FILE}")
    print(f"Run ID: {run_id}  (pass --run-id {run_id} --resume to continue on failure)")
    print(f"Applied={summary['applied']}  Planned={summary['planned']}  "
          f"Clean={summary['clean']}  Failed={summary['failed']}")
    return 1 if summary["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
