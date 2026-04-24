# AWS Landing Zone — Account Creation Automation

> Repository-specific instructions for Copilot. General workflow, coding style, and persona preferences are in `common.instructions.md` (user-level) — do not duplicate them here.

## What This Repository Does

This repository implements a **custom AWS Landing Zone** (alternative to AWS LZA/Control Tower AFT) using Terraform. It automates multi-account provisioning: account onboarding via Control Tower, SCP/tag policy governance, IAM Identity Center SSO configuration, security baseline deployment (GuardDuty, Security Hub, Config, CloudTrail, Access Analyzer), and infrastructure services (networking, logging, backup, cost reporting). It is a **Terraform + Python + GitHub Actions** project — not a web application.

## AWS Multi-Account Architecture

### Organizational Unit (OU) Structure
```
Root
├── Security           # GuardDuty delegated admin, Security Hub, audit accounts
├── Infrastructure     # Shared services, networking, logging accounts
│   └── shared-services
├── Workloads
│   ├── Production     # prod-* accounts — strictest SCPs + prod_restricted policy
│   ├── Staging        # staging-* accounts
│   └── Development    # dev-* accounts — dev_sandbox policy
└── Sandbox            # Temporary experimentation — most permissive
```

### Core AWS Services by Stack

| Stack | AWS Services | Key Resources |
|---|---|---|
| `00-bootstrap` | S3, DynamoDB | State bucket + lock table (versioned, encrypted, public access blocked) |
| `01-organizations` | Organizations, SCPs | OUs, delegated admins, tag policies, backup policies, AI opt-out |
| `02-security` | Security Hub, GuardDuty, Config, Detective, Inspector, Macie | Org-wide enablement, delegated admin, conformance packs |
| `03-networking` | VPC, Transit Gateway, VPN, Direct Connect, Network Firewall, Route53, VPC IPAM | Multi-account routing, VPC endpoints (S3/DynamoDB), flow logs |
| `04-logging` | CloudTrail, S3, Kinesis Firehose, CloudWatch | Centralized logging bucket + access logs + CloudWatch→S3 pipeline |
| `05-operations` | SSM, Backup, Cost Explorer, Budgets | Patch baselines, maintenance windows, backup vaults with WORM |
| `06-workload-support` | CloudFormation StackSets, Service Catalog, ALB/NLB, Auto Scaling | Self-service provisioning, workload infrastructure |
| `account-setup` | IAM, Identity Center (SSO), Access Analyzer | Per-account baseline: password policy, EBS encryption, S3 block |
| `landing-zone` | All of the above | Master orchestrator — 19 feature-flagged modules |
| `permission-sets` | SSO Admin | Permission set definitions + customer-managed policy attachments |

### Service Control Policies (SCPs)

| SCP | Attached To | Purpose |
|---|---|---|
| `DenyOutsideAllowedRegions` | All member OUs | Blocks operations outside `us-east-1`, `us-west-2` (exempts global services: IAM, STS, Organizations, CloudFront, Route53) |
| `DenyRootAccount` | Root OU | Denies all root user actions in member accounts |
| `SecurityGuardrails` | Root OU | Prevents disabling GuardDuty, Security Hub, Config, CloudTrail, Access Analyzer; blocks leaving Organization or closing accounts |

### Cross-Account Access Patterns

- **Management → Target Account**: `aws.target` provider assumes role into member account for baseline deployment
- **Management → Identity Center**: `aws.sso` provider resolves permission sets and IdP groups (synced via SCIM)
- **Control Tower → Lambda → GitHub**: EventBridge captures `CreateManagedAccount` → SNS → Lambda → `workflow_dispatch`
- **Lambda → Secrets Manager**: Retrieves GitHub PAT via `secretsmanager.get_secret_value()` (not hardcoded)

### Account Factory Trigger Pipeline
```
Control Tower creates account
    → EventBridge rule (CreateManagedAccount event)
    → SNS topic
    → Lambda function (Python 3.12)
    → GitHub Actions workflow_dispatch
    → account-setup stack (per-account Terraform state)
```

## Tech Stack & Versions

| Layer | Technology | Version Constraint |
|---|---|---|
| IaC | Terraform (HCL) | `>= 1.5` (CI uses `~> 1.9`) |
| Provider | AWS | `~> 6.0` |
| Runtime | Python | `3.12` (Lambda) / `3.13` (CI scripts) |
| Config parsing | PyYAML | `>= 6.0.1, < 7.0` |
| HCL serialization | python-hcl2 | `>= 5.0, < 6.0` |
| Testing | pytest | `>= 7.0, < 9.0` |
| CI/CD | GitHub Actions | OIDC auth to AWS |

## Project Layout

```
.github/workflows/          # 3 workflows: account-setup, landing-zone, permission-sets
accounts/requests/           # YAML account request files (GitOps trigger)
config/                      # YAML configs: global.yaml, landing-zone.yaml, per-stack configs
modules/                     # 22 Terraform modules (account-baseline, networking, security, etc.)
stacks/                      # 10 Terraform stacks — each has own state in S3
  00-bootstrap/              # Run FIRST — creates S3 state bucket + DynamoDB lock table
  01-organizations/          # AWS Organizations + governance (SCPs, tag policies)
  02-security/               # Security Hub, GuardDuty, Config rules
  03-networking/             # Transit Gateway, VPCs, Route53
  04-logging/                # Centralized CloudTrail, VPC Flow Logs
  05-operations/             # SSM, Backup, Cost Explorer
  06-workload-support/       # Shared services for workloads
  account-setup/             # Per-account baseline (policies, SSO, security settings)
  landing-zone/              # Master orchestrator — 19 feature-flagged modules
  permission-sets/           # SSO permission set definitions
scripts/
  hcl_writer.py              # Custom HCL2 serializer: dict_to_hcl(), write_tfvars()
  resolve_account.py         # Account ID + name → policy/SSO resolution via account_policy_map.yaml
  process_account_requests.py# Processes YAML request files from accounts/requests/
  generate_landing_zone_tfvars.py  # config/landing-zone.yaml → stacks/landing-zone/terraform.tfvars
  generate_stack_tfvars.py   # Per-stack config → tfvars generation
policies/                    # IAM policy JSON files (admin, dev_sandbox, prod_restricted, viewer)
account_policy_map.yaml      # Single source of truth: account → policy + SSO assignment mapping
tests/                       # 125 pytest tests across 5 test files
```

## Build, Test & Validate

Always install dependencies first:
```bash
pip install -r requirements.txt
```

Run all tests (125 tests, should all pass):
```bash
cd "$(git rev-parse --show-toplevel)"
python -m pytest tests/ -v
```

Generate landing-zone tfvars:
```bash
python3 scripts/generate_landing_zone_tfvars.py
# Output: stacks/landing-zone/terraform.tfvars
```

Generate per-stack tfvars:
```bash
python3 scripts/generate_stack_tfvars.py --stack 01-organizations
# Or all stacks: python3 scripts/generate_stack_tfvars.py --all
```

Terraform validation (any stack):
```bash
cd stacks/<stack-name>
terraform init -backend=false
terraform validate
terraform fmt -check
```

## Key Data Flow

1. **Account request** → `accounts/requests/<name>.yaml` pushed to `main`
2. **GitHub Actions** detects changed YAML → runs `process_account_requests.py`
3. **Policy resolution** via `account_policy_map.yaml`: exact account ID → prefix rules (`prod-`, `dev-`, etc.) → default
4. **Output** → `terraform.tfvars` (native HCL2 format via `hcl_writer.py` — NOT JSON)
5. **Terraform plan/apply** in `stacks/account-setup/` with per-account state key

Alternative trigger: **Control Tower** creates account → EventBridge → SNS → **Lambda** (`modules/account-factory-trigger/lambda/index.py`) → GitHub `workflow_dispatch`

## Critical Conventions

- **All tfvars are native HCL2** — generated by `scripts/hcl_writer.py`, never hand-written JSON
- **S3 backend** for all stacks: bucket `acme-lz-terraform-state`, lock table `acme-lz-terraform-locks`
- **Feature flags** in landing-zone: `count = var.enable_<feature> ? 1 : 0` pattern
- **Lambda skips** accounts named: `log-archive`, `audit`, `shared-services` (env: `SKIP_ACCOUNT_NAMES`)
- **Lambda retries**: 3 attempts with `2^attempt` exponential backoff on 5xx/403/429
- **Permission sets** reference customer-managed policies by NAME (not ARN) — policies live in target accounts
- **Concurrency control** on all CI workflows to prevent parallel Terraform state corruption
- **OIDC authentication** — no long-lived AWS credentials in GitHub; role assumed via `aws-actions/configure-aws-credentials`

## Security Requirements

- Never hardcode AWS credentials, account IDs, or secrets in code
- All S3 buckets must have versioning, encryption (`aws_kms_key`), and `aws_s3_bucket_public_access_block`
- Validate all external inputs: account IDs must match `^\d{12}$`, account names must match `^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$`
- Before installing any pip package, check for known CVEs (Snyk/OSV) — install only if risk is acceptable, uninstall after one-time use
- Pin third-party GitHub Actions to SHA commits, not tags
- All KMS keys must have key rotation enabled and restrictive key policies
- IAM roles follow least-privilege: scope permissions to specific resources/actions, never use `*/*` wildcards
- Security services (GuardDuty, Security Hub, Config, CloudTrail) must never be disabled in member accounts — enforced by `SecurityGuardrails` SCP
- Secrets (GitHub PAT) stored in AWS Secrets Manager, retrieved at runtime — never in environment variables or code
- EBS encryption enabled by default in all accounts (`aws_ebs_encryption_by_default`)
- S3 account-level public access block on all accounts (`aws_s3_account_public_access_block`)
- Backup vaults use WORM lock configuration for compliance

## Terraform Conventions

- Provider version: `~> 6.0` — always check AWS provider changelog before upgrading
- Use `terraform fmt` before committing any `.tf` file
- Module inputs go in `variables.tf`, outputs in `outputs.tf`, provider constraints in `versions.tf`
- All resources must include standard tags: `Org`, `Program`, `Owner`, `CostCenter`, `ManagedBy = "terraform"`
- State key pattern for account-setup: `account-setup/{account_id}/terraform.tfstate`
- Landing-zone modules use `count = var.enable_<feature> ? 1 : 0` — access outputs as `module.<name>[0].<output>`
- Use `aws_organizations_organization` data source (not resource) when reading org state across stacks
- Multi-provider pattern: `aws.target` (member account), `aws.sso` (Identity Center), default `aws` (management)
- CloudFormation StackSets use `SERVICE_MANAGED` deployment mode for org-wide rollout
- Use `aws_ssoadmin_customer_managed_policy_attachment` (by policy NAME) — never `aws_ssoadmin_managed_policy_attachment` for custom policies

## Python Conventions

- All scripts use `argparse` for CLI interface — maintain this pattern
- YAML parsing via `yaml.safe_load()` — never use `yaml.load()` (unsafe deserialization)
- HCL output via `hcl_writer.write_tfvars(data, path)` — never write tfvars manually
- Scripts must work from repository root (`sys.path` includes `scripts/`)
- Error messages go to `sys.stderr`; structured output to `sys.stdout`
- Test files mirror script names: `test_resolve_account.py` tests `resolve_account.py`
- Lambda uses `urllib.request` for GitHub API calls — no `requests` library (keep Lambda lightweight)
- Lambda uses `boto3` only for Secrets Manager (`secretsmanager.get_secret_value`) — initialized outside handler for connection reuse
- Policy resolution order in `account_policy_map.yaml`: exact account ID match → prefix rules (`prod-`, `dev-`, `staging-`, `sandbox-`) → default
- Account request YAML fields: `account_name`, `email`, `ou`, `environment` (production|staging|development|sandbox)

## GitHub Actions Conventions

- All workflows use `id-token: write` + `contents: read` permissions (OIDC)
- Terraform steps: init → validate → plan → apply (apply only on `main` push or manual dispatch)
- Every workflow has a `notify-failure` job that sends to SNS on failure
- Concurrency groups prevent parallel runs per workflow
- Account-setup workflow supports 3 trigger types: `workflow_dispatch`, `push`, and Lambda `workflow_dispatch`


