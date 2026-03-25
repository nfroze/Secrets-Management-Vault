#!/usr/bin/env bash
# =============================================================================
# Analyse Vault Audit Logs
# Reads the audit log from vault-0 and produces a summary of:
#   - Total operations
#   - Operations by type (request/response)
#   - Top accessed paths (which secrets are being read)
#   - Auth method usage
#   - Error rates
#
# Vault audit logs are JSON — one line per operation with full
# request/response details and HMAC-hashed sensitive values.
# =============================================================================

set -euo pipefail

NAMESPACE="vault"
POD="vault-0"
AUDIT_LOG="/vault/audit/vault-audit.log"
LINES="${1:-100}"

echo "========================================="
echo "  Vault Audit Log Analysis"
echo "  Last ${LINES} entries from ${POD}"
echo "========================================="
echo ""

# Extract audit log
AUDIT_DATA=$(kubectl exec -n "${NAMESPACE}" "${POD}" -- tail -n "${LINES}" "${AUDIT_LOG}" 2>/dev/null)

if [ -z "${AUDIT_DATA}" ]; then
  echo "No audit log entries found. Ensure audit logging is enabled."
  echo "  Run: ./scripts/enable-audit-logging.sh"
  exit 0
fi

TOTAL=$(echo "${AUDIT_DATA}" | wc -l)
echo "Total entries: ${TOTAL}"
echo ""

# Operations by type
echo "--- Operations by Type ---"
echo "${AUDIT_DATA}" | jq -r '.type // "unknown"' 2>/dev/null | sort | uniq -c | sort -rn
echo ""

# Top accessed paths
echo "--- Top Accessed Paths ---"
echo "${AUDIT_DATA}" | jq -r '.request.path // "unknown"' 2>/dev/null | sort | uniq -c | sort -rn | head -15
echo ""

# Auth methods used
echo "--- Auth Methods ---"
echo "${AUDIT_DATA}" | jq -r '.auth.accessor // .request.mount_accessor // "unknown"' 2>/dev/null | sort | uniq -c | sort -rn
echo ""

# Operations by mount
echo "--- Operations by Mount ---"
echo "${AUDIT_DATA}" | jq -r '.request.mount_type // "system"' 2>/dev/null | sort | uniq -c | sort -rn
echo ""

# Errors
ERROR_COUNT=$(echo "${AUDIT_DATA}" | jq -r 'select(.error != null and .error != "") | .error' 2>/dev/null | wc -l)
echo "--- Errors ---"
echo "Total errors: ${ERROR_COUNT}"
if [ "${ERROR_COUNT}" -gt 0 ]; then
  echo ""
  echo "Recent errors:"
  echo "${AUDIT_DATA}" | jq -r 'select(.error != null and .error != "") | "\(.time) | \(.request.path) | \(.error)"' 2>/dev/null | tail -5
fi

echo ""
echo "========================================="
echo "  Analysis complete"
echo "  For full log: kubectl exec -n vault vault-0 -- cat ${AUDIT_LOG}"
echo "========================================="
