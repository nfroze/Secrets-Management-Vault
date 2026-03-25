#!/usr/bin/env bash
# =============================================================================
# Setup Vault Secrets Operator (VSO)
# Creates the CA cert secret in the VSO namespace, applies VaultConnection
# and VaultAuth CRDs, then deploys the app-namespace secret sync resources.
#
# Prerequisites:
#   1. Vault is running and configured (secrets engines + auth methods)
#   2. VSO Helm release is deployed (terraform apply)
#   3. TLS certificates generated (generate-vault-tls.sh)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "========================================="
echo "  Vault Secrets Operator Setup"
echo "========================================="

# Step 1: Copy Vault CA cert into VSO namespace
echo "[1/4] Creating CA cert secret in VSO namespace..."
kubectl create secret generic vault-tls-ca \
  --namespace=vault-secrets-operator-system \
  --from-file=ca.crt="${PROJECT_DIR}/vault/tls/ca.crt" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  CA cert secret created."

# Step 2: Apply VaultConnection and VaultAuth
echo "[2/4] Applying VaultConnection and VaultAuth..."
kubectl apply -f "${PROJECT_DIR}/kubernetes/vault-secrets-operator/vault-connection.yaml"
kubectl apply -f "${PROJECT_DIR}/kubernetes/vault-secrets-operator/vault-auth.yaml"

echo "  VaultConnection and VaultAuth created."

# Step 3: Create app namespace and its VaultAuth
echo "[3/4] Setting up app namespace..."
kubectl apply -f "${PROJECT_DIR}/kubernetes/app-namespace.yaml"

# Create demo-app service account
kubectl create serviceaccount demo-app \
  --namespace=app \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${PROJECT_DIR}/kubernetes/vault-secrets-operator/app-vault-auth.yaml"

echo "  App namespace and VaultAuth created."

# Step 4: Apply secret sync resources
echo "[4/4] Deploying secret sync CRDs..."
kubectl apply -f "${PROJECT_DIR}/kubernetes/vault-secrets-operator/database-secret.yaml"
kubectl apply -f "${PROJECT_DIR}/kubernetes/vault-secrets-operator/aws-secret.yaml"
kubectl apply -f "${PROJECT_DIR}/kubernetes/vault-secrets-operator/pki-secret.yaml"
kubectl apply -f "${PROJECT_DIR}/kubernetes/vault-secrets-operator/transit-key-config.yaml"

echo "  Secret sync CRDs deployed."

# Verify
echo ""
echo "Verifying synced secrets..."
sleep 10

echo ""
echo "Secrets in 'app' namespace:"
kubectl get secrets -n app -l app.kubernetes.io/part-of=demo-app

echo ""
echo "VaultDynamicSecret status:"
kubectl get vaultdynamicsecrets -n app

echo ""
echo "VaultPKISecret status:"
kubectl get vaultpkisecrets -n app

echo ""
echo "VaultStaticSecret status:"
kubectl get vaultstaticsecrets -n app

echo ""
echo "========================================="
echo "  VSO setup complete!"
echo "  Secrets are now synced into the 'app' namespace."
echo "  Applications consume them as standard K8s Secrets."
echo "========================================="
