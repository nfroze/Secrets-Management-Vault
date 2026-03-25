#!/usr/bin/env bash
# =============================================================================
# Verify All Vault Secrets Engines Are Operational
# Generates test credentials from each engine and validates the output.
# =============================================================================

set -euo pipefail

PASS=0
FAIL=0

check() {
  local name="$1"
  local cmd="$2"
  echo -n "  Testing ${name}... "
  if eval "${cmd}" &>/dev/null; then
    echo "PASS"
    ((PASS++))
  else
    echo "FAIL"
    ((FAIL++))
  fi
}

echo "========================================="
echo "  Vault Secrets Engine Verification"
echo "========================================="

if [ -z "${VAULT_ADDR:-}" ] || [ -z "${VAULT_TOKEN:-}" ]; then
  echo "ERROR: VAULT_ADDR and VAULT_TOKEN must be set"
  exit 1
fi

echo ""
echo "Secrets Engines:"
check "Database (readonly)" "vault read -format=json database/creds/readonly"
check "Database (readwrite)" "vault read -format=json database/creds/readwrite"
check "AWS (s3-readwrite)" "vault read -format=json aws/creds/s3-readwrite"
check "PKI (issue cert)" "vault write -format=json pki_int/issue/internal-service common_name=test.svc.cluster.local ttl=1h"
check "Transit (encrypt)" "vault write -format=json transit/encrypt/app-data plaintext=$(echo -n 'verification-test' | base64)"

echo ""
echo "Auth Methods:"
check "Kubernetes auth" "vault read -format=json auth/kubernetes/role/app"
check "AppRole auth" "vault read -format=json auth/approle/role/cicd"

echo ""
echo "Policies:"
for policy in admin app-full database-readonly database-readwrite aws-credentials pki-issue transit-encrypt; do
  check "Policy: ${policy}" "vault policy read ${policy}"
done

echo ""
echo "Audit:"
check "Audit logging" "vault audit list -format=json"

echo ""
echo "========================================="
echo "  Results: ${PASS} passed, ${FAIL} failed"
if [ "${FAIL}" -gt 0 ]; then
  echo "  Some checks failed. Review output above."
  exit 1
else
  echo "  All secrets engines operational."
fi
echo "========================================="
