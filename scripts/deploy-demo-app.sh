#!/usr/bin/env bash
# =============================================================================
# Build and deploy the demo application to EKS
#
# Prerequisites:
#   1. EKS cluster running, kubectl configured
#   2. Vault configured with all secrets engines
#   3. VSO deployed and secret sync CRDs applied
#   4. Docker available (for building the image)
#
# The demo app consumes ALL secrets through standard Kubernetes Secrets.
# No Vault SDK. No sidecar injector. Pure Kubernetes-native consumption.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${PROJECT_DIR}/app"
NAMESPACE="app"
AWS_REGION="eu-west-2"

echo "========================================="
echo "  Demo Application Deployment"
echo "========================================="

# Get AWS account ID for ECR
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/secrets-vault-demo"

# Step 1: Create ECR repository
echo "[1/5] Creating ECR repository..."
aws ecr create-repository \
  --repository-name secrets-vault-demo \
  --region "${AWS_REGION}" \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 \
  2>/dev/null || echo "  (already exists)"

# Step 2: Build Docker image
echo "[2/5] Building Docker image..."
cd "${APP_DIR}"
docker build -t secrets-vault-demo:latest .

# Step 3: Push to ECR
echo "[3/5] Pushing to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker tag secrets-vault-demo:latest "${ECR_REPO}:latest"
docker push "${ECR_REPO}:latest"

# Step 4: Update deployment image reference
echo "[4/5] Deploying to EKS..."
cd "${PROJECT_DIR}"

# Apply namespace and service account (may already exist from VSO setup)
kubectl apply -f kubernetes/app-namespace.yaml
kubectl create serviceaccount demo-app \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Update image in deployment manifest and apply
sed "s|image: demo-app:latest|image: ${ECR_REPO}:latest|" \
  "${APP_DIR}/kubernetes/deployment.yaml" | kubectl apply -f -

kubectl apply -f "${APP_DIR}/kubernetes/service.yaml"
kubectl apply -f "${APP_DIR}/kubernetes/networkpolicy.yaml"

# Step 5: Wait for rollout
echo "[5/5] Waiting for deployment..."
kubectl rollout status deployment/demo-app -n "${NAMESPACE}" --timeout=120s

echo ""
echo "========================================="
echo "  Demo app deployed!"
echo ""
echo "  Port-forward: kubectl port-forward svc/demo-app 8080:80 -n app"
echo "  Health:       curl http://localhost:8080/health"
echo "  Init DB:      curl -X POST http://localhost:8080/api/init-db"
echo "  Credentials:  curl http://localhost:8080/api/credentials/summary"
echo "========================================="
