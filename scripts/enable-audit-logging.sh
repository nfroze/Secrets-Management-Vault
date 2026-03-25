#!/usr/bin/env bash
# =============================================================================
# Enable Vault Audit Logging
# File-based audit log written to the audit PVC volume.
# Every secret access, generation, and revocation is logged
# with full request/response details.
# =============================================================================

set -euo pipefail

echo "========================================="
echo "  Vault Audit Log Configuration"
echo "========================================="

if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
  echo "ERROR: VAULT_ADDR and VAULT_TOKEN must be set"
  exit 1
fi

# Enable file audit device
vault audit enable file \
  file_path="/vault/audit/vault-audit.log" \
  log_raw=false \
  hmac_accessor=true \
  2>/dev/null || echo "  (already enabled)"

echo "  Audit log: /vault/audit/vault-audit.log"
echo "  HMAC: enabled (sensitive values hashed)"
echo "  Raw logging: disabled"

# Verify
vault audit list -format=json | jq -r 'to_entries[] | "  \(.key): \(.value.type) → \(.value.options.file_path // "n/a")"'

echo ""
echo "========================================="
echo "  Audit logging active"
echo "  Every Vault operation is now logged."
echo "========================================="
