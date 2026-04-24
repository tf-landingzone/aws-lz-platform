---
applyTo: ".github/workflows/**/*.yml,.github/workflows/**/*.yaml"
---

## GitHub Actions Rules for This Repository

### AWS Authentication
- All workflows use OIDC authentication: `id-token: write` + `contents: read` permissions
- Role assumed via `aws-actions/configure-aws-credentials` — never use long-lived AWS credentials
- AWS region: `us-east-1` (primary) — global services (IAM, Organizations, CloudFront) are region-agnostic
- Role ARN stored in GitHub secrets as `AWS_ROLE_ARN` — never hardcoded in workflow files
- OIDC trust policy must scope to this specific repository and branch

### Terraform CI/CD
- Terraform version pinned to `~> 1.9` in CI
- Terraform steps always follow: init → validate → plan → apply
- Apply only runs on `main` push or `workflow_dispatch` — never on pull requests
- Concurrency groups required on all workflows to prevent parallel Terraform state corruption (S3 + DynamoDB locking)
- Always include `timeout-minutes` on jobs to prevent hung workflows
- Pin third-party actions to SHA commits, not tags

### Workflow-Specific Rules
- **account-setup**: Handles 3 trigger types: manual `workflow_dispatch`, `push` (GitOps YAML files), and Lambda-initiated `workflow_dispatch` (from Control Tower EventBridge → Lambda)
- **account-setup**: Uses per-account state key: `account-setup/{account_id}/terraform.tfstate` — each account gets isolated state
- **account-setup**: `auto_approve` input only for Lambda-triggered runs (Control Tower already validated the account)
- **landing-zone**: Regenerates tfvars before plan: `python3 scripts/generate_landing_zone_tfvars.py`
- **landing-zone**: Triggers on changes to `config/landing-zone.yaml`, `modules/**`, `stacks/landing-zone/**`
- **permission-sets**: Uses `environment: production` for manual approval gates before applying SSO changes
- Every workflow must have a `notify-failure` job that sends to SNS (`AWS_SNS_TOPIC_ARN` secret)

### AWS-Specific CI Considerations
- Control Tower account creation is async — Lambda polls/retries until account is ready
- SCP changes affect all accounts in an OU immediately — always plan carefully before applying `01-organizations`
- Identity Center changes (permission sets) require propagation time — CI should not run multiple permission-set applies concurrently
- GuardDuty/Security Hub delegated admin changes can only be made from the management account
- Terraform state contains sensitive data (account IDs, role ARNs) — S3 state bucket must have encryption + versioning
