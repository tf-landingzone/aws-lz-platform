#!/usr/bin/env bash
###############################################################################
# tf-executor entrypoint — orchestrates Terraform for one account
#
# Step sequence:
#   1. Download account_policy_map.yaml from S3  →  /app/account_policy_map.yaml
#   2. resolve_account.py  →  generates /app/.deploy_workdir/<id>/terraform.tfvars
#   3. Copy stack TF files → isolated per-account workdir
#   4. terraform init  (per-account state key in S3)
#   5. terraform validate
#   6. terraform plan  -detailed-exitcode
#   7. terraform apply (unless PLAN_ONLY=true or no changes)
#   8. Write result to DynamoDB lz-account-inventory
#
# All output is written to stdout/stderr → CloudWatch Logs via awslogs driver.
###############################################################################

set -euo pipefail

# ── Validate required inputs ──────────────────────────────────────────────────
: "${ACCOUNT_ID:?ACCOUNT_ID is required}"
: "${ACCOUNT_NAME:?ACCOUNT_NAME is required}"
: "${TF_STATE_BUCKET:?TF_STATE_BUCKET is required}"
: "${AWS_REGION:?AWS_REGION is required}"

# ── Defaults ──────────────────────────────────────────────────────────────────
ENVIRONMENT="${ENVIRONMENT:-auto}"
OU="${OU:-}"
PLAN_ONLY="${PLAN_ONLY:-false}"
LZ_INVENTORY_TABLE="${LZ_INVENTORY_TABLE:-lz-account-inventory}"
POLICY_MAP_S3_KEY="${POLICY_MAP_S3_KEY:-config/account_policy_map.yaml}"
# S3 prefix where sync-runtime-to-s3.yml publishes the current code artefacts.
# Layout under this prefix mirrors /app/:
#   runtime/stack/     → stacks/account-setup/*.tf
#   runtime/modules/   → modules/account-baseline/**
#   runtime/policies/  → policies/*.json
#   runtime/scripts/   → scripts/resolve_account.py + hcl_writer.py
RUNTIME_S3_PREFIX="${RUNTIME_S3_PREFIX:-runtime}"

WORK_DIR="/app/.deploy_workdir/${ACCOUNT_ID}"
STACK_SRC="/app/stacks/account-setup"
POLICY_MAP_LOCAL="/app/account_policy_map.yaml"
TF_VARS="${WORK_DIR}/terraform.tfvars"

echo "==================================================================="
echo " tf-executor  v1.1  (runtime-sync model)"
echo " account_id  : ${ACCOUNT_ID}"
echo " account_name: ${ACCOUNT_NAME}"
echo " environment : ${ENVIRONMENT}"
echo " ou          : ${OU:-<none>}"
echo " plan_only   : ${PLAN_ONLY}"
echo " state_bucket: ${TF_STATE_BUCKET}  region: ${AWS_REGION}"
echo " runtime s3  : s3://${TF_STATE_BUCKET}/${RUNTIME_S3_PREFIX}/"
echo "==================================================================="

mkdir -p "${WORK_DIR}" "${TF_PLUGIN_CACHE_DIR:-/tmp/tf-plugin-cache}"

# ── 0. Sync current runtime artefacts from S3 ────────────────────────────────
# The Docker image contains ONLY the runtime (terraform + python + awscli).
# All Terraform stack files, modules, policies, and scripts are stored in S3
# and synced here at task startup. This means code changes (policy updates,
# module changes, stack changes) take effect immediately without rebuilding
# the image. The image only needs to be rebuilt when the runtime itself
# changes (new Terraform version, new Python dependency, entrypoint logic).
echo ""
echo "[0/7] Syncing runtime artefacts from s3://${TF_STATE_BUCKET}/${RUNTIME_S3_PREFIX}/"

aws s3 sync \
    "s3://${TF_STATE_BUCKET}/${RUNTIME_S3_PREFIX}/stack/" \
    "/app/stacks/account-setup/" \
    --region "${AWS_REGION}" --no-progress --delete

aws s3 sync \
    "s3://${TF_STATE_BUCKET}/${RUNTIME_S3_PREFIX}/modules/" \
    "/app/modules/" \
    --region "${AWS_REGION}" --no-progress --delete

aws s3 sync \
    "s3://${TF_STATE_BUCKET}/${RUNTIME_S3_PREFIX}/policies/" \
    "/app/policies/" \
    --region "${AWS_REGION}" --no-progress --delete

aws s3 sync \
    "s3://${TF_STATE_BUCKET}/${RUNTIME_S3_PREFIX}/scripts/" \
    "/app/scripts/" \
    --region "${AWS_REGION}" --no-progress --delete

echo "Runtime sync complete."

# ── 1. Download account_policy_map.yaml ───────────────────────────────────────
echo ""
echo "[1/7] Downloading policy map from s3://${TF_STATE_BUCKET}/${POLICY_MAP_S3_KEY}"
aws s3 cp "s3://${TF_STATE_BUCKET}/${POLICY_MAP_S3_KEY}" "${POLICY_MAP_LOCAL}" \
    --region "${AWS_REGION}" --no-progress

# ── 2. Generate terraform.tfvars via resolve_account.py ──────────────────────
echo ""
echo "[2/7] Generating tfvars for ${ACCOUNT_NAME}"
ENV_ARG=()
if [[ "${ENVIRONMENT}" != "auto" ]]; then
    ENV_ARG=(--environment "${ENVIRONMENT}")
fi
python3 /app/scripts/resolve_account.py \
    "${ACCOUNT_ID}" "${ACCOUNT_NAME}" \
    "${ENV_ARG[@]}" \
    --output "${TF_VARS}"

# ── 3. Assemble per-account workdir ──────────────────────────────────────────
echo ""
echo "[3/7] Preparing isolated workdir"
# Copy TF files — each account gets its own .terraform/ to avoid races
# Also copy the lock file so provider versions are pinned reproducibly
cp "${STACK_SRC}"/*.tf "${WORK_DIR}/"
[[ -f "${STACK_SRC}/.terraform.lock.hcl" ]] && cp "${STACK_SRC}/.terraform.lock.hcl" "${WORK_DIR}/"

# ── 4. terraform init ─────────────────────────────────────────────────────────
echo ""
echo "[4/7] terraform init"
terraform -chdir="${WORK_DIR}" init \
    -backend-config="bucket=${TF_STATE_BUCKET}" \
    -backend-config="key=account-setup/${ACCOUNT_ID}/terraform.tfstate" \
    -backend-config="region=${AWS_REGION}" \
    -no-color -input=false -reconfigure

# ── 5. terraform validate ─────────────────────────────────────────────────────
echo ""
echo "[5/7] terraform validate"
terraform -chdir="${WORK_DIR}" validate -no-color

# ── 6. terraform plan ─────────────────────────────────────────────────────────
echo ""
echo "[6/7] terraform plan"
set +e
terraform -chdir="${WORK_DIR}" plan \
    -var-file="${TF_VARS}" \
    -detailed-exitcode \
    -out="${WORK_DIR}/tfplan" \
    -no-color -input=false 2>&1 | tee /tmp/plan_output.txt
PLAN_EXIT=${PIPESTATUS[0]}
set -e

if [[ ${PLAN_EXIT} -eq 1 ]]; then
    echo "ERROR: terraform plan failed for ${ACCOUNT_NAME}"
    exit 1
fi

TF_STATUS="clean"

if [[ ${PLAN_EXIT} -eq 2 ]]; then
    if [[ "${PLAN_ONLY}" == "true" ]]; then
        echo "plan-only mode — skipping apply"
        TF_STATUS="planned"
    else
        echo ""
        echo "[6/7] terraform apply"
        terraform -chdir="${WORK_DIR}" apply \
            -auto-approve -no-color -input=false \
            "${WORK_DIR}/tfplan"
        TF_STATUS="applied"
    fi
fi

echo ""
echo "Terraform status: ${TF_STATUS}"

# ── 7. Write result to DynamoDB ───────────────────────────────────────────────
echo ""
echo "[7/7] Recording result to DynamoDB (${LZ_INVENTORY_TABLE})"
python3 - <<'PY'
import boto3, os, time

ddb   = boto3.resource('dynamodb', region_name=os.environ['AWS_REGION'])
table = ddb.Table(os.environ['LZ_INVENTORY_TABLE'])

table.put_item(Item={
    'account_id':       os.environ['ACCOUNT_ID'],
    'account_name':     os.environ['ACCOUNT_NAME'],
    'environment':      os.environ.get('ENVIRONMENT', 'auto'),
    'ou':               os.environ.get('OU', ''),
    'status':           'provisioned',
    'tf_status':        os.environ['TF_STATUS'],
    'last_deployed_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    'state_key': f"account-setup/{os.environ['ACCOUNT_ID']}/terraform.tfstate",
})
print(f"Recorded: {os.environ['ACCOUNT_ID']} → {os.environ['TF_STATUS']}")
PY

echo "==================================================================="
echo " DONE: ${ACCOUNT_NAME} (${ACCOUNT_ID}) — ${TF_STATUS}"
echo "==================================================================="
