#!/usr/bin/env bash
# =============================================================================
# Configure GitHub Actions Secrets for Vault AppRole Authentication
#
# Only THREE secrets are stored in GitHub:
#   1. VAULT_ADDR       — Vault cluster endpoint
#   2. VAULT_ROLE_ID    — AppRole Role ID (non-sensitive identifier)
#   3. VAULT_SECRET_ID  — AppRole Secret ID (single-use, short-lived)
#
# No AWS credentials are stored in GitHub. The pipeline authenticates
# to Vault via AppRole and retrieves dynamic AWS credentials on demand.
#
# Prerequisites:
#   1. gh CLI authenticated (gh auth login)
#   2. Vault configured with AppRole auth (configure-secrets-engines.sh)
#   3. VAULT_ADDR and VAULT_TOKEN environment variables set
# =============================================================================

set -euo pipefail

REPO="nfroze/Secrets-Management-Vault"

echo "========================================="
echo "  GitHub Actions Secrets Setup"
echo "========================================="

if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
  echo "ERROR: VAULT_ADDR and VAULT_TOKEN must be set"
  exit 1
fi

# Get the AppRole Role ID
echo "[1/3] Retrieving AppRole Role ID..."
ROLE_ID=$(vault read -format=json auth/approle/role/cicd/role-id | jq -r '.data.role_id')
echo "  Role ID: ${ROLE_ID}"

# Generate a Secret ID
echo "[2/3] Generating AppRole Secret ID..."
SECRET_ID=$(vault write -format=json -force auth/approle/role/cicd/secret-id | jq -r '.data.secret_id')
echo "  Secret ID generated (single-use)"

# Set GitHub secrets
echo "[3/3] Setting GitHub secrets..."
echo "${VAULT_ADDR}" | gh secret set VAULT_ADDR --repo="${REPO}"
echo "${ROLE_ID}" | gh secret set VAULT_ROLE_ID --repo="${REPO}"
echo "${SECRET_ID}" | gh secret set VAULT_SECRET_ID --repo="${REPO}"

echo ""
echo "========================================="
echo "  GitHub secrets configured!"
echo ""
echo "  Secrets set on ${REPO}:"
echo "    - VAULT_ADDR"
echo "    - VAULT_ROLE_ID"
echo "    - VAULT_SECRET_ID"
echo ""
echo "  NOTE: VAULT_SECRET_ID is single-use."
echo "  Regenerate before each pipeline run or"
echo "  configure a wrapped token delivery mechanism."
echo "========================================="
