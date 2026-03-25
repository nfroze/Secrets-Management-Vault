#!/usr/bin/env bash
# =============================================================================
# Configure Vault Secrets Engines, Auth Methods, and Policies
#
# Prerequisites:
#   1. Vault is initialized and unsealed
#   2. VAULT_ADDR and VAULT_TOKEN environment variables are set
#   3. Terraform outputs available (RDS endpoint, etc.)
#
# This script configures:
#   - Database secrets engine (PostgreSQL dynamic credentials)
#   - AWS secrets engine (dynamic IAM credentials)
#   - PKI secrets engine (internal CA for service-to-service TLS)
#   - Transit secrets engine (encryption as a service)
#   - Kubernetes auth method
#   - AppRole auth method (for CI/CD)
#   - All Vault policies
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "========================================="
echo "  Vault Secrets Engine Configuration"
echo "========================================="

# Validate prerequisites
if [ -z "${VAULT_ADDR:-}" ]; then
  echo "ERROR: VAULT_ADDR not set. Export it first."
  echo "  export VAULT_ADDR=https://localhost:8200"
  exit 1
fi

if [ -z "${VAULT_TOKEN:-}" ]; then
  echo "ERROR: VAULT_TOKEN not set. Export the root token."
  exit 1
fi

# Get Terraform outputs
echo "[0/8] Reading Terraform outputs..."
cd "${PROJECT_DIR}/terraform"

RDS_ENDPOINT=$(terraform output -raw rds_address)
RDS_DB_NAME=$(terraform output -raw rds_db_name)
RDS_PASSWORD=$(terraform output -raw rds_master_password)
VAULT_ROLE_ARN=$(terraform output -raw vault_iam_role_arn)
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name)

cd "${PROJECT_DIR}"

echo "  RDS Endpoint: ${RDS_ENDPOINT}"
echo "  Database:     ${RDS_DB_NAME}"
echo ""

########################################
# 1. POLICIES
########################################
echo "[1/8] Writing policies..."

for policy_file in vault/policies/*.hcl; do
  policy_name=$(basename "${policy_file}" .hcl)
  vault policy write "${policy_name}" "${policy_file}"
  echo "  Policy: ${policy_name}"
done

echo ""

########################################
# 2. DATABASE SECRETS ENGINE
########################################
echo "[2/8] Configuring database secrets engine..."

vault secrets enable -path=database database 2>/dev/null || echo "  (already enabled)"

# Configure the PostgreSQL connection
# The pgx driver requires sslrootcert as a file path — the RDS CA bundle
# is volume-mounted into Vault pods at /vault/certs/rds-ca-bundle.pem
vault write database/config/postgres \
  plugin_name="postgresql-database-plugin" \
  allowed_roles="readonly,readwrite" \
  connection_url="postgresql://{{username}}:{{password}}@${RDS_ENDPOINT}:5432/${RDS_DB_NAME}?sslmode=verify-full&sslrootcert=/vault/certs/rds-ca-bundle.pem" \
  username="vaultadmin" \
  password="${RDS_PASSWORD}" \
  password_authentication="scram-sha-256"

# Rotate the root credential immediately so the Terraform-known password is invalidated
vault write -force database/rotate-root/postgres
echo "  Root credential rotated (Terraform password invalidated)"

# Readonly role — SELECT only, 1h default TTL, 24h max
vault write database/roles/readonly \
  db_name="postgres" \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT CONNECT ON DATABASE ${RDS_DB_NAME} TO \"{{name}}\";
    GRANT USAGE ON SCHEMA public TO \"{{name}}\";
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO \"{{name}}\";
  " \
  revocation_statements="
    SELECT pg_terminate_backend(pg_stat_activity.pid)
      FROM pg_stat_activity
      WHERE usename = '{{name}}' AND pid <> pg_backend_pid();
    REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\";
    REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM \"{{name}}\";
    REVOKE USAGE ON SCHEMA public FROM \"{{name}}\";
    REVOKE CONNECT ON DATABASE ${RDS_DB_NAME} FROM \"{{name}}\";
    DROP ROLE IF EXISTS \"{{name}}\";
  " \
  default_ttl="1h" \
  max_ttl="24h"

echo "  Role: readonly (1h TTL, 24h max)"

# Read-write role — full DML access, 1h default TTL, 24h max
vault write database/roles/readwrite \
  db_name="postgres" \
  creation_statements="
    CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';
    GRANT CONNECT ON DATABASE ${RDS_DB_NAME} TO \"{{name}}\";
    GRANT USAGE ON SCHEMA public TO \"{{name}}\";
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO \"{{name}}\";
  " \
  revocation_statements="
    SELECT pg_terminate_backend(pg_stat_activity.pid)
      FROM pg_stat_activity
      WHERE usename = '{{name}}' AND pid <> pg_backend_pid();
    REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\";
    REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM \"{{name}}\";
    REVOKE USAGE ON SCHEMA public FROM \"{{name}}\";
    REVOKE CONNECT ON DATABASE ${RDS_DB_NAME} FROM \"{{name}}\";
    DROP ROLE IF EXISTS \"{{name}}\";
  " \
  default_ttl="1h" \
  max_ttl="24h"

echo "  Role: readwrite (1h TTL, 24h max)"
echo ""

########################################
# 3. AWS SECRETS ENGINE
########################################
echo "[3/8] Configuring AWS secrets engine..."

vault secrets enable -path=aws aws 2>/dev/null || echo "  (already enabled)"

# Configure root — uses IRSA, no static credentials needed
# Vault inherits IAM permissions from the pod's service account via IRSA
vault write aws/config/root \
  region="eu-west-2"

# S3 read-write role — generates IAM users with scoped S3 access
vault write aws/roles/s3-readwrite \
  credential_type="iam_user" \
  policy_document='
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${var.project_name}-*",
        "arn:aws:s3:::${var.project_name}-*/*"
      ]
    }
  ]
}' \
  default_ttl="1h" \
  max_ttl="4h"

echo "  Role: s3-readwrite (iam_user, 1h TTL)"
echo ""

########################################
# 4. PKI SECRETS ENGINE — ROOT CA
########################################
echo "[4/8] Configuring PKI secrets engine (Root CA)..."

vault secrets enable -path=pki pki 2>/dev/null || echo "  (already enabled)"

# Set max TTL for root CA (10 years)
vault secrets tune -max-lease-ttl=87600h pki

# Generate root CA certificate
vault write -format=json pki/root/generate/internal \
  common_name="Secrets Vault Root CA" \
  issuer_name="root-ca" \
  ttl="87600h" \
  key_bits=4096 \
  organization="Secrets Vault" \
  country="GB" \
  > /tmp/pki-root-ca.json

echo "  Root CA generated (10-year TTL)"

# Configure CA and CRL URLs
vault write pki/config/urls \
  issuing_certificates="https://vault.vault.svc.cluster.local:8200/v1/pki/ca" \
  crl_distribution_points="https://vault.vault.svc.cluster.local:8200/v1/pki/crl"

########################################
# 5. PKI SECRETS ENGINE — INTERMEDIATE CA
########################################
echo "[5/8] Configuring PKI secrets engine (Intermediate CA)..."

vault secrets enable -path=pki_int pki 2>/dev/null || echo "  (already enabled)"

# Set max TTL for intermediate (5 years)
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate intermediate CSR
vault write -format=json pki_int/intermediate/generate/internal \
  common_name="Secrets Vault Intermediate CA" \
  issuer_name="intermediate-ca" \
  key_bits=4096 \
  organization="Secrets Vault" \
  country="GB" \
  > /tmp/pki-intermediate-csr.json

INTERMEDIATE_CSR=$(jq -r '.data.csr' /tmp/pki-intermediate-csr.json)

# Sign the intermediate CSR with the root CA
vault write -format=json pki/root/sign-intermediate \
  csr="${INTERMEDIATE_CSR}" \
  format="pem_bundle" \
  ttl="43800h" \
  > /tmp/pki-intermediate-signed.json

SIGNED_CERT=$(jq -r '.data.certificate' /tmp/pki-intermediate-signed.json)

# Import the signed certificate back into the intermediate CA mount
vault write pki_int/intermediate/set-signed \
  certificate="${SIGNED_CERT}"

echo "  Intermediate CA signed by Root CA (5-year TTL)"

# Configure URLs for intermediate
vault write pki_int/config/urls \
  issuing_certificates="https://vault.vault.svc.cluster.local:8200/v1/pki_int/ca" \
  crl_distribution_points="https://vault.vault.svc.cluster.local:8200/v1/pki_int/crl"

# Create a role for issuing internal service certificates
vault write pki_int/roles/internal-service \
  allowed_domains="svc.cluster.local,vault.svc.cluster.local" \
  allow_subdomains=true \
  allow_bare_domains=false \
  allow_glob_domains=true \
  max_ttl="720h" \
  ttl="72h" \
  key_bits=2048 \
  key_type="rsa" \
  require_cn=false \
  generate_lease=true \
  organization="Secrets Vault" \
  country="GB"

echo "  Role: internal-service (72h default, 720h max)"
echo ""

########################################
# 6. TRANSIT SECRETS ENGINE
########################################
echo "[6/8] Configuring transit secrets engine..."

vault secrets enable -path=transit transit 2>/dev/null || echo "  (already enabled)"

# Create encryption key for application data
# aes256-gcm96 is the default and most widely supported type
# NOT setting derived=true (would require context on every operation)
# NOT setting exportable=true (keys should never leave Vault)
vault write -force transit/keys/app-data \
  type="aes256-gcm96" \
  deletion_allowed=false \
  exportable=false \
  allow_plaintext_backup=false

echo "  Key: app-data (aes256-gcm96, non-exportable)"

# Enable automatic key rotation every 90 days
vault write transit/keys/app-data/config \
  auto_rotate_period="2160h" \
  min_decryption_version=1 \
  min_encryption_version=0

echo "  Auto-rotation: every 90 days"
echo ""

########################################
# 7. KUBERNETES AUTH METHOD
########################################
echo "[7/8] Configuring Kubernetes auth method..."

vault auth enable -path=kubernetes kubernetes 2>/dev/null || echo "  (already enabled)"

# Configure with in-cluster service account
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc.cluster.local:443"

# Role: app — binds to the demo app service account
vault write auth/kubernetes/role/app \
  bound_service_account_names="demo-app" \
  bound_service_account_namespaces="app" \
  policies="app-full" \
  audience="vault" \
  ttl="1h" \
  max_ttl="4h"

echo "  Role: app (SA: demo-app, NS: app, policy: app-full)"

# Role: vault-secrets-operator — binds to VSO service account
vault write auth/kubernetes/role/vault-secrets-operator \
  bound_service_account_names="vault-secrets-operator-controller-manager" \
  bound_service_account_namespaces="vault-secrets-operator-system" \
  policies="app-full" \
  audience="vault" \
  ttl="1h" \
  max_ttl="4h"

echo "  Role: vault-secrets-operator (for VSO)"
echo ""

########################################
# 8. APPROLE AUTH METHOD (CI/CD)
########################################
echo "[8/8] Configuring AppRole auth method..."

vault auth enable -path=approle approle 2>/dev/null || echo "  (already enabled)"

# CI/CD pipeline role — admin access for deployments
vault write auth/approle/role/cicd \
  secret_id_ttl="10m" \
  token_ttl="20m" \
  token_max_ttl="1h" \
  token_policies="admin" \
  secret_id_num_uses=1

echo "  Role: cicd (single-use secret ID, 20m token TTL)"

# Read role ID (needed for GitHub Actions)
ROLE_ID=$(vault read -format=json auth/approle/role/cicd/role-id | jq -r '.data.role_id')
echo "  Role ID: ${ROLE_ID}"
echo ""
echo "  To generate a Secret ID (do this per-pipeline run):"
echo "    vault write -force auth/approle/role/cicd/secret-id"

# Cleanup temp files
rm -f /tmp/pki-root-ca.json /tmp/pki-intermediate-csr.json /tmp/pki-intermediate-signed.json

echo ""
echo "========================================="
echo "  All secrets engines configured!"
echo ""
echo "  Test database creds:  vault read database/creds/readonly"
echo "  Test AWS creds:       vault read aws/creds/s3-readwrite"
echo "  Test PKI cert:        vault write pki_int/issue/internal-service common_name=test.svc.cluster.local"
echo "  Test transit encrypt: vault write transit/encrypt/app-data plaintext=\$(echo 'hello' | base64)"
echo "========================================="
