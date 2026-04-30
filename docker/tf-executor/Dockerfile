###############################################################################
# tf-executor — Fargate task image for account-setup Terraform runs
#
# WHAT THIS IMAGE CONTAINS (runtime only — intentionally minimal):
#   /usr/local/bin/terraform  — Terraform binary
#   /usr/local/bin/aws        — AWS CLI v2
#   Python 3.12 + boto3 + pyyaml
#   /entrypoint.sh            — orchestration script
#
# WHAT IS NOT BAKED IN (fetched from S3 at task startup):
#   stacks/account-setup/*.tf    → s3://<bucket>/runtime/stack/
#   modules/account-baseline/    → s3://<bucket>/runtime/modules/
#   policies/*.json              → s3://<bucket>/runtime/policies/
#   scripts/resolve_account.py   → s3://<bucket>/runtime/scripts/
#
# WHY:
#   Baking code into the image means every policy change, module fix, or
#   stack update triggers a full Docker build + ECR push + task definition
#   update — for a text file change. Instead, code lives in S3 and is synced
#   by sync-runtime-to-s3.yml in ~30 seconds. Fargate picks it up on the
#   next task run. The image only needs rebuilding when the RUNTIME changes
#   (new Terraform version, new Python dep, entrypoint logic).
#
# Runtime environment variables (injected by Step Functions → ECS):
#   ACCOUNT_ID          — 12-digit AWS account ID (required)
#   ACCOUNT_NAME        — e.g. prod-app-001 (required)
#   ENVIRONMENT         — production|staging|development|sandbox|auto
#   OU                  — OU name (e.g. Production)
#   PLAN_ONLY           — "true" | "false"
#   TF_STATE_BUCKET     — S3 bucket for Terraform state + runtime artefacts
#   AWS_REGION          — AWS region (required)
#   LZ_INVENTORY_TABLE  — DynamoDB table for account inventory
#   RUNTIME_S3_PREFIX   — S3 prefix for runtime artefacts (default: runtime)
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

# Create empty directories that entrypoint.sh will populate via s3 sync.
# Keeping them here makes the directory structure predictable and avoids
# entrypoint needing to mkdir before syncing.
RUN mkdir -p \
    /app/stacks/account-setup \
    /app/modules \
    /app/policies \
    /app/scripts \
    /app/.deploy_workdir

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
