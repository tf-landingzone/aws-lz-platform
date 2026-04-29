#!/usr/bin/env python3
"""
Generate a human-readable drift summary from deploy-report.json.

Reads DRIFT_RUN_URL from environment for the GitHub Actions run link.
Exits 0 with no output when there is nothing to report (no drift).
"""
import json
import os
import sys


def main() -> None:
    try:
        with open("deploy-report.json") as fh:
            report = json.load(fh)
    except Exception as exc:
        print(f"Cannot parse deploy-report.json: {exc}", file=sys.stderr)
        sys.exit(0)

    results = report.get("results", [])
    remediated = [r for r in results if r.get("status") == "applied"]
    detected = [r for r in results if r.get("status") == "planned"]

    if not remediated and not detected:
        sys.exit(0)  # no output → caller skips the alert

    lines = []
    if remediated:
        lines.append(f"Auto-remediated drift in {len(remediated)} account(s):")
        for r in remediated:
            lines.append(f"  - {r['account_id']} ({r['account_name']})")
    if detected:
        lines.append(f"Drift detected (plan-only) in {len(detected)} account(s):")
        for r in detected:
            lines.append(f"  - {r['account_id']} ({r['account_name']})")

    run_url = os.environ.get("DRIFT_RUN_URL", "")
    if run_url:
        lines.append(f"\nRun: {run_url}")

    print("\n".join(lines))


if __name__ == "__main__":
    main()
