#!/usr/bin/env bash
# =============================================================================
# Deploy HashiCorp Vault to EKS via Helm
# Prerequisites:
#   1. EKS cluster provisioned (terraform apply)
#   2. kubectl configured (aws eks update-kubeconfig)
#   3. TLS secrets created (generate-vault-tls.sh)
#   4. RDS CA secret created (create-rds-ca-secret.sh)
#   5. StorageClass applied (kubectl apply -f kubernetes/storage-class.yaml)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
NAMESPACE="vault"
RELEASE_NAME="vault"

echo "========================================="
echo "  Vault Helm Deployment"
echo "========================================="

# Get Terraform outputs for Helm values substitution
echo "[1/5] Reading Terraform outputs..."
cd "${PROJECT_DIR}/terraform"

AWS_REGION=$(terraform output -raw 2>/dev/null | grep -oP '(?<=aws_region = ).*' || echo "eu-west-2")
AWS_REGION="${AWS_REGION:-eu-west-2}"
VAULT_IAM_ROLE_ARN=$(terraform output -raw vault_iam_role_arn)
KMS_KEY_ID=$(terraform output -raw vault_kms_key_id)

echo "  Region:         ${AWS_REGION}"
echo "  Vault IAM Role: ${VAULT_IAM_ROLE_ARN}"
echo "  KMS Key ID:     ${KMS_KEY_ID}"

cd "${PROJECT_DIR}"

# Substitute variables in Helm values
echo "[2/5] Preparing Helm values..."
sed \
  -e "s|\${VAULT_IAM_ROLE_ARN}|${VAULT_IAM_ROLE_ARN}|g" \
  -e "s|\${AWS_REGION}|${AWS_REGION}|g" \
  -e "s|\${KMS_KEY_ID}|${KMS_KEY_ID}|g" \
  vault/helm-values.yaml > /tmp/vault-helm-values-resolved.yaml

# Apply prerequisites
echo "[3/5] Applying prerequisites..."
kubectl apply -f kubernetes/vault-namespace.yaml
kubectl apply -f kubernetes/storage-class.yaml

# Verify secrets exist
for secret in vault-tls rds-ca-bundle; do
  if ! kubectl get secret "${secret}" -n "${NAMESPACE}" &>/dev/null; then
    echo "ERROR: Secret '${secret}' not found in namespace '${NAMESPACE}'"
    echo "Run the prerequisite scripts first."
    exit 1
  fi
done
echo "  Prerequisites verified."

# Add Helm repo
echo "[4/5] Adding HashiCorp Helm repo..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install/upgrade Vault
echo "[5/5] Installing Vault..."
helm upgrade --install "${RELEASE_NAME}" hashicorp/vault \
  --namespace "${NAMESPACE}" \
  --values /tmp/vault-helm-values-resolved.yaml \
  --wait \
  --timeout 10m

# Cleanup
rm -f /tmp/vault-helm-values-resolved.yaml

echo ""
echo "========================================="
echo "  Vault deployed successfully!"
echo "  Run: ./scripts/init-vault.sh"
echo "========================================="
