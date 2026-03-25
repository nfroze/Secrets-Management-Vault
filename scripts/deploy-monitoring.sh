#!/usr/bin/env bash
# =============================================================================
# Deploy monitoring stack and Vault-specific resources
#
# Prerequisites:
#   1. EKS cluster running, kubectl configured
#   2. kube-prometheus-stack deployed via Terraform
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "========================================="
echo "  Monitoring Stack Deployment"
echo "========================================="

# Apply Vault ServiceMonitor
echo "[1/3] Deploying Vault ServiceMonitor..."
kubectl apply -f "${PROJECT_DIR}/kubernetes/monitoring/vault-servicemonitor.yaml"
echo "  ServiceMonitor created."

# Apply Grafana dashboard ConfigMap
echo "[2/3] Deploying Grafana dashboard..."
kubectl apply -f "${PROJECT_DIR}/kubernetes/monitoring/vault-grafana-dashboard.yaml"
echo "  Dashboard ConfigMap created."

# Apply alert rules
echo "[3/3] Deploying Prometheus alert rules..."
kubectl apply -f "${PROJECT_DIR}/kubernetes/monitoring/vault-alerts.yaml"
echo "  Alert rules created."

echo ""
echo "========================================="
echo "  Monitoring deployed!"
echo ""
echo "  Grafana:     kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring"
echo "  Prometheus:  kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring"
echo "  Credentials: admin / vault-demo-admin"
echo ""
echo "  Vault dashboard: Dashboards → Vault → Vault Overview"
echo "========================================="
