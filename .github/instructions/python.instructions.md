---
applyTo: "scripts/**/*.py,tests/**/*.py,modules/**/lambda/**/*.py"
---

## Python Rules for This Repository

### Runtime & Dependencies
- Runtime: Python 3.12 (Lambda) / 3.13 (CI scripts)
- Dependencies: PyYAML `>=6.0.1,<7.0`, python-hcl2 `>=5.0,<6.0`, pytest `>=7.0,<9.0`
- Install deps first: `pip install -r requirements.txt`
- Run tests: `python -m pytest tests/ -v` (125 tests, all must pass)
- Before installing any pip package, check for known CVEs via Snyk/OSV

### Script Conventions
- Always use `yaml.safe_load()` — never `yaml.load()` (unsafe deserialization)
- All scripts use `argparse` for CLI — maintain this pattern
- HCL output via `hcl_writer.write_tfvars(data, path)` — never write `.tfvars` manually or as JSON
- Error messages to `sys.stderr`; structured output to `sys.stdout`
- Scripts run from repository root — `sys.path` includes `scripts/`
- Test files mirror script names: `test_resolve_account.py` tests `resolve_account.py`

### AWS Input Validation
- Account IDs must match `^\d{12}$` — always validate before use
- Account names must match `^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$`
- OU names must exist in `config/landing-zone.yaml` `organizational_units` section
- Environment must be one of: `production`, `staging`, `development`, `sandbox`

### Policy Resolution (account_policy_map.yaml)
- Resolution order: exact account ID → prefix rules (`prod-`, `staging-`, `dev-`, `sandbox-`) → default
- Each rule contains: `policies` (IAM policy name + file), `assignments` (SSO permission set + IdP group), `security_baseline` (account hardening flags)
- Security baseline flags: `enable_password_policy`, `enable_ebs_encryption`, `enable_s3_public_access_block`, `enable_access_analyzer`

### Lambda Function (Account Factory Trigger)
- Lambda skips accounts: `log-archive`, `audit`, `shared-services` (env: `SKIP_ACCOUNT_NAMES`)
- Lambda retry: 3 attempts, `2^attempt` exponential backoff, retries on 5xx/403/429 only
- Uses `urllib.request` for GitHub API calls — no `requests` library (keep Lambda package minimal)
- Uses `boto3` only for `secretsmanager.get_secret_value()` — initialized outside handler for connection reuse
- GitHub PAT retrieved from AWS Secrets Manager at runtime — never from environment variables
- Event source: SNS (from EventBridge `CreateManagedAccount` event from Control Tower)
- DLQ: SQS queue with CloudWatch alarm for monitoring failed invocations
- Never hardcode AWS account IDs, GitHub tokens, or repository names in Lambda code
