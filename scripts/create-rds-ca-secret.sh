#!/usr/bin/env bash
# =============================================================================
# Download AWS RDS CA bundle and create Kubernetes secret
# Required for Vault's database secrets engine to connect to RDS over SSL.
# The pgx PostgreSQL driver needs the CA cert as a file path on disk,
# so we volume-mount this secret into the Vault pods.
# =============================================================================

set -euo pipefail

NAMESPACE="vault"
SECRET_NAME="rds-ca-bundle"
CA_BUNDLE_URL="https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"
TEMP_DIR=$(mktemp -d)

echo "========================================="
echo "  RDS CA Bundle Secret Creation"
echo "========================================="

# Download the global RDS CA bundle
echo "[1/2] Downloading RDS CA bundle..."
curl -sSL "${CA_BUNDLE_URL}" -o "${TEMP_DIR}/rds-ca-bundle.pem"

# Verify the file is valid PEM
if ! openssl x509 -in "${TEMP_DIR}/rds-ca-bundle.pem" -noout 2>/dev/null; then
  echo "WARNING: File may contain a certificate bundle (multiple certs). Verifying first cert..."
  head -n 30 "${TEMP_DIR}/rds-ca-bundle.pem" | openssl x509 -noout 2>/dev/null || {
    echo "ERROR: Downloaded file is not a valid PEM certificate"
    rm -rf "${TEMP_DIR}"
    exit 1
  }
fi

CERT_COUNT=$(grep -c "BEGIN CERTIFICATE" "${TEMP_DIR}/rds-ca-bundle.pem")
echo "  Downloaded bundle contains ${CERT_COUNT} certificates"

# Create Kubernetes secret
echo "[2/2] Creating Kubernetes secret..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "${SECRET_NAME}" \
  --namespace="${NAMESPACE}" \
  --from-file=rds-ca-bundle.pem="${TEMP_DIR}/rds-ca-bundle.pem" \
  --dry-run=client -o yaml | kubectl apply -f -

# Cleanup
rm -rf "${TEMP_DIR}"

echo ""
echo "========================================="
echo "  Secret '${SECRET_NAME}' created"
echo "  in namespace '${NAMESPACE}'"
echo "  Mount path in Vault: /vault/certs/rds-ca-bundle.pem"
echo "========================================="
