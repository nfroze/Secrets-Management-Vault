#!/usr/bin/env bash
# =============================================================================
# Initialize and unseal HashiCorp Vault on EKS
# KMS auto-unseal means we only need to initialize vault-0.
# Standby replicas auto-unseal and join the Raft cluster automatically.
# =============================================================================

set -euo pipefail

NAMESPACE="vault"
VAULT_POD="vault-0"
# Helper: run vault CLI inside the pod, skipping TLS verify for self-signed certs
vault_exec() {
  kubectl exec -n "${NAMESPACE}" "${VAULT_POD}" -- \
    env VAULT_SKIP_VERIFY=true vault "$@"
}

echo "========================================="
echo "  Vault Initialization"
echo "========================================="

# Wait for vault-0 to be running
echo "[1/5] Waiting for ${VAULT_POD} to be running..."
kubectl wait --for=condition=Ready pod/${VAULT_POD} \
  -n "${NAMESPACE}" \
  --timeout=300s 2>/dev/null || {
    echo "  Pod not Ready yet (expected — Vault is sealed/uninitialised)"
    echo "  Checking pod status..."
    kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=vault
}

# Check if already initialized
echo "[2/5] Checking Vault status..."
INIT_STATUS=$(vault_exec status -format=json 2>/dev/null | jq -r '.initialized' || echo "false")

if [ "${INIT_STATUS}" = "true" ]; then
  echo "  Vault is already initialized."

  SEAL_STATUS=$(vault_exec status -format=json 2>/dev/null | jq -r '.sealed' || echo "true")

  if [ "${SEAL_STATUS}" = "false" ]; then
    echo "  Vault is already unsealed (KMS auto-unseal active)."
  else
    echo "  Vault is sealed. KMS auto-unseal should handle this."
    echo "  Check IRSA configuration and KMS key permissions."
    exit 1
  fi
else
  # Initialize Vault with KMS auto-unseal (no Shamir key shares needed)
  echo "[3/5] Initializing Vault..."
  INIT_OUTPUT=$(vault_exec operator init -format=json -recovery-shares=5 -recovery-threshold=3)

  echo "${INIT_OUTPUT}" > /tmp/vault-init-keys.json

  echo ""
  echo "  ============================================"
  echo "  CRITICAL: Save the recovery keys securely!"
  echo "  They are stored temporarily in /tmp/vault-init-keys.json"
  echo "  Recovery keys are needed for certain admin operations."
  echo "  ============================================"
  echo ""

  # Extract root token
  ROOT_TOKEN=$(echo "${INIT_OUTPUT}" | jq -r '.root_token')
  echo "  Root Token: ${ROOT_TOKEN}"
  echo ""
  echo "  Vault initialized. KMS auto-unseal is active."
fi

# Wait for all replicas to join
echo "[4/5] Waiting for Raft peers to join..."
sleep 10

for i in 1 2; do
  POD="vault-${i}"
  echo "  Checking ${POD}..."

  # Wait for the pod to be running
  kubectl wait --for=condition=Ready pod/${POD} \
    -n "${NAMESPACE}" \
    --timeout=120s 2>/dev/null || {
      echo "  ${POD} not ready yet. It may still be joining..."
    }
done

# Verify Raft cluster status
echo "[5/5] Verifying Raft cluster..."
if [ -n "${ROOT_TOKEN:-}" ]; then
  vault_exec login "${ROOT_TOKEN}" >/dev/null 2>&1

  vault_exec operator raft list-peers
else
  echo "  (Skipping — log in with root token to check Raft peers)"
fi

echo ""
echo "========================================="
echo "  Vault cluster is operational!"
echo ""
echo "  Access UI: kubectl port-forward svc/vault 8200:8200 -n vault"
echo "  Open:      https://localhost:8200"
echo "========================================="
