# aws-lz-platform

**Terraform engine** for the AWS Landing Zone. Owns all infrastructure-as-code — stacks, config, and the reusable deployment workflow.

---

## What this repo deploys (AWS resources)

### 00-bootstrap (run FIRST — one time)
| AWS Resource | Name | Purpose |
|---|---|---|
| S3 Bucket | `{org}-lz-terraform-state` | Remote state storage — versioned + KMS encrypted |
| S3 Bucket | `{org}-lz-terraform-state-replica` | DR replica in secondary region |
| DynamoDB Table | `{org}-lz-terraform-locks` | State file locking (prevents concurrent runs) |
| DynamoDB Table | `{org}-lz-deploy-run-state` | Pipeline resume-on-failure checkpoint table |
| IAM OIDC Provider | `token.actions.githubusercontent.com` | GitHub Actions → AWS authentication (no static keys) |
| IAM Role | `github-actions-deploy` | Role GitHub Actions assumes via OIDC |

### 01-organizations
| AWS Resource | Purpose |
|---|---|
| AWS Organizations OUs | Workloads-Prod, Workloads-Dev, Sandbox, Security, Logging |
| Service Control Policies | Attached per OU (from aws-lz-policies repo) |

### 02-security
| AWS Resource | Purpose |
|---|---|
| AWS GuardDuty | Threat detection — org-wide delegated to security account |
| AWS Security Hub | Aggregated findings — CIS + AWS Foundational standards |
| AWS IAM Access Analyzer | Cross-account access analysis |
| AWS Detective | Security investigation (optional) |
| AWS Inspector | Container + Lambda vulnerability scanning |
| AWS Macie | S3 sensitive data discovery |

### 03-networking
| AWS Resource | Purpose |
|---|---|
| VPC + Subnets | Hub spoke per region (Transit Gateway attached) |
| Transit Gateway | Cross-account / cross-OU routing |
| Route53 Resolver | Private DNS across accounts |
| ACM Certificates | Wildcard certs per domain |

### 04-logging
| AWS Resource | Purpose |
|---|---|
| S3 Bucket | Centralized CloudTrail + Config logs |
| CloudTrail (org-wide) | API audit trail for all accounts |
| AWS Config (org-wide) | Resource inventory + compliance rules |

### 05-operations
| AWS Resource | Purpose |
|---|---|
| SSM Parameter Store | Cross-stack value sharing |
| AWS Backup | Centralized backup policies |
| Cost & Usage Reports | Budget alerts per account/OU |

### account-setup (runs per new account)
| AWS Resource | Purpose |
|---|---|
| IAM Policies | Custom policies pushed into the target account |
| SSO Account Assignment | Maps IdP group → permission set → account |
| Security Baseline | Password policy, EBS encryption, S3 public access block |

### account-factory-trigger (EventBridge automation)
| AWS Resource | Purpose |
|---|---|
| EventBridge Rule | Detects Control Tower `CreateManagedAccount` success event |
| SNS Topic | Bridges EventBridge → Lambda |
| SQS Queue (DLQ) | Lambda dead-letter queue — failed events retried |
| **Lambda Function** | Parses account ID/name from CT event → dispatches GitHub Actions workflow |
| IAM Role | Lambda execution role with Secrets Manager read access |
| Secrets Manager Secret | Stores GitHub PAT for workflow dispatch |

---

## Stacks (apply order)

```
stacks/
├── 00-bootstrap/        ← 1st: S3 state + DynamoDB + OIDC
├── 01-organizations/    ← 2nd: OUs + SCPs
├── 02-security/         ← 3rd: GuardDuty, Security Hub, Inspector...
├── 03-networking/       ← 4th: VPC, TGW, DNS
├── 04-logging/          ← 5th: CloudTrail, Config, S3 log bucket
├── 05-operations/       ← 6th: SSM, Backup, Budgets
├── 06-workload-support/ ← 7th: Support configs for workload accounts
├── landing-zone/        ← Orchestrates 01-06 as single apply
├── permission-sets/     ← IAM Identity Center permission sets
└── account-setup/       ← Per-account: policies + SSO + baseline
```

---

## Workflows

| Workflow | Trigger | What it does |
|---|---|---|
| `landing-zone.yml` | Push to main / manual | Applies stacks 01-06 in order |
| `permission-sets.yml` | Push to main / manual | Applies permission-sets stack |
| `account-deploy-reusable.yml` | Called by aws-lz-accounts | Plans + applies account-setup stack for one account |
| `account-setup-drift-sweep.yml` | Nightly 02:00 UTC | Re-applies all accounts to fix drift |
| `terratest.yml` | PR | Go-based integration tests |

---

## Prerequisites before first apply

1. AWS Management Account with Control Tower enabled
2. Run `00-bootstrap` locally first (bootstraps the remote state backend)
3. Set these GitHub Actions secrets in this repo:

| Secret | Value |
|---|---|
| `AWS_ROLE_ARN` | ARN of `github-actions-deploy` IAM role (created by 00-bootstrap) |
| `SNS_NOTIFICATION_TOPIC_ARN` | Optional — for failure alerts |

---

## Config

All stack behaviour is driven by `config/*.yaml`:

```
config/
├── global.yaml           ← org name, region, cost center, tags
├── landing-zone.yaml     ← OUs, accounts list, SCP assignments
├── 01-organizations.yaml
├── 02-security.yaml      ← enable/disable GuardDuty, Security Hub etc.
├── 03-networking.yaml    ← CIDR ranges, regions
├── 04-logging.yaml
├── 05-operations.yaml
└── 06-workload-support.yaml
```

Edit `config/global.yaml` first — all other configs inherit from it.
