###############################################################################
# tf-executor — Fargate task image for account-setup Terraform runs
#
# What it contains (assembled by .github/workflows/build-tf-executor.yml):
#   /app/stacks/account-setup/*.tf    — stack TF files (aws-lz-platform)
#   /app/modules/account-baseline/   — Terraform module (aws-tf-modules)
#   /app/policies/*.json             — IAM policy files (aws-lz-policies)
#   /app/scripts/resolve_account.py  — resolver script (aws-lz-accounts)
#   /app/scripts/hcl_writer.py       — HCL writer (aws-lz-accounts)
#   /entrypoint.sh                   — orchestration script
#
# Directory layout mirrors the monorepo path structure so that relative
# Terraform source paths (../../modules/account-baseline) resolve correctly
# from .deploy_workdir/<account_id>/:
#   path.root = /app/.deploy_workdir/<account_id>/
#   ../../modules/account-baseline → /app/modules/account-baseline  ✔
#   ../../policies/admin.json      → /app/policies/admin.json        ✔
#
# Runtime environment variables (injected by Step Functions → ECS):
#   ACCOUNT_ID          — 12-digit AWS account ID (required)
#   ACCOUNT_NAME        — e.g. prod-app-001 (required)
#   ENVIRONMENT         — production|staging|development|sandbox|auto
#   OU                  — OU name (e.g. Production)
#   PLAN_ONLY           — "true" | "false"
#   TF_STATE_BUCKET     — S3 bucket for Terraform state (required)
#   AWS_REGION          — AWS region (required)
#   LZ_INVENTORY_TABLE  — DynamoDB table for account inventory
#   POLICY_MAP_S3_KEY   — S3 key for account_policy_map.yaml
###############################################################################

ARG TF_VERSION=1.9.5

# ── Stage 1: terraform binary ─────────────────────────────────────────────────
FROM hashicorp/terraform:${TF_VERSION} AS tf-binary

# ── Stage 2: final image ──────────────────────────────────────────────────────
FROM python:3.12-slim

ARG TF_VERSION=1.9.5
LABEL org.opencontainers.image.description="LZ tf-executor — terraform runner for account-setup stack"
LABEL lz.terraform.version="${TF_VERSION}"

# Copy terraform binary
COPY --from=tf-binary /bin/terraform /usr/local/bin/terraform

# System deps: git (for terraform module downloads), awscli, ca-certs
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl unzip git && \
    # Install AWS CLI v2
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscli.zip && \
    unzip -q /tmp/awscli.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/aws /tmp/awscli.zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Python deps
RUN pip install --no-cache-dir boto3==1.35.* pyyaml==6.*

# ── Application layout ────────────────────────────────────────────────────────
WORKDIR /app

# Stack TF files (from aws-lz-platform — baked at image build time)
COPY stacks/account-setup/ /app/stacks/account-setup/

# Terraform module (from aws-tf-modules — baked at image build time)
COPY modules/account-baseline/ /app/modules/account-baseline/

# IAM policy JSON files (from aws-lz-policies — baked at image build time)
COPY policies/ /app/policies/

# Python scripts (from aws-lz-accounts — copied by build workflow)
COPY scripts/ /app/scripts/

# Entrypoint
COPY docker/tf-executor/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ── Terraform configuration ───────────────────────────────────────────────────
# Shared plugin cache across all parallel tasks on the same host.
# TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=1 is required because
# multiple accounts share the lock file hash but use the same binaries.
ENV TF_PLUGIN_CACHE_DIR=/tmp/tf-plugin-cache
ENV TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=1
ENV TF_IN_AUTOMATION=1
ENV TF_INPUT=0

ENTRYPOINT ["/entrypoint.sh"]
