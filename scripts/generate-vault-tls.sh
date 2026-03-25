#!/usr/bin/env bash
# =============================================================================
# Generate TLS certificates for Vault internal communication
# Creates a self-signed CA + server certificate with SANs for all Vault pods
# =============================================================================

set -euo pipefail

# Prevent MINGW64 (Git Bash on Windows) from converting /C=GB/... to Windows paths
export MSYS_NO_PATHCONV=1

# Use pwd -W on MINGW64 to get Windows-native paths for openssl
if [ -n "${MSYSTEM:-}" ]; then
  CERT_DIR="$(cd "$(dirname "$0")/.." && pwd -W)/vault/tls"
else
  CERT_DIR="$(cd "$(dirname "$0")/.." && pwd)/vault/tls"
fi
NAMESPACE="vault"
SERVICE="vault"
SECRET_NAME="vault-tls"

echo "========================================="
echo "  Vault TLS Certificate Generation"
echo "========================================="

mkdir -p "${CERT_DIR}"

# Generate CA private key
openssl genrsa -out "${CERT_DIR}/ca.key" 4096

# Generate CA certificate
openssl req -x509 -new -nodes \
  -key "${CERT_DIR}/ca.key" \
  -sha256 -days 3650 \
  -out "${CERT_DIR}/ca.crt" \
  -subj "/C=GB/ST=London/O=Secrets-Vault/CN=Vault CA"

# Generate server private key
openssl genrsa -out "${CERT_DIR}/tls.key" 4096

# Create CSR config with SANs for all Vault pods + services
cat > "${CERT_DIR}/csr.conf" <<EOF
[req]
default_bits       = 4096
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = v3_req

[dn]
C  = GB
ST = London
O  = Secrets-Vault
CN = vault

[v3_req]
basicConstraints     = CA:FALSE
keyUsage             = digitalSignature, keyEncipherment
extendedKeyUsage     = serverAuth, clientAuth
subjectAltName       = @alt_names

[alt_names]
DNS.1  = ${SERVICE}
DNS.2  = ${SERVICE}.${NAMESPACE}
DNS.3  = ${SERVICE}.${NAMESPACE}.svc
DNS.4  = ${SERVICE}.${NAMESPACE}.svc.cluster.local
DNS.5  = ${SERVICE}-internal
DNS.6  = ${SERVICE}-internal.${NAMESPACE}
DNS.7  = ${SERVICE}-internal.${NAMESPACE}.svc
DNS.8  = ${SERVICE}-internal.${NAMESPACE}.svc.cluster.local
DNS.9  = vault-0.${SERVICE}-internal
DNS.10 = vault-0.${SERVICE}-internal.${NAMESPACE}.svc.cluster.local
DNS.11 = vault-1.${SERVICE}-internal
DNS.12 = vault-1.${SERVICE}-internal.${NAMESPACE}.svc.cluster.local
DNS.13 = vault-2.${SERVICE}-internal
DNS.14 = vault-2.${SERVICE}-internal.${NAMESPACE}.svc.cluster.local
DNS.15 = localhost
IP.1   = 127.0.0.1
EOF

# Generate CSR
openssl req -new \
  -key "${CERT_DIR}/tls.key" \
  -out "${CERT_DIR}/tls.csr" \
  -config "${CERT_DIR}/csr.conf"

# Sign the certificate with the CA
openssl x509 -req \
  -in "${CERT_DIR}/tls.csr" \
  -CA "${CERT_DIR}/ca.crt" \
  -CAkey "${CERT_DIR}/ca.key" \
  -CAcreateserial \
  -out "${CERT_DIR}/tls.crt" \
  -days 365 \
  -sha256 \
  -extensions v3_req \
  -extfile "${CERT_DIR}/csr.conf"

echo ""
echo "Certificates generated in ${CERT_DIR}"
echo ""

# Create Kubernetes secret
echo "Creating Kubernetes TLS secret..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "${SECRET_NAME}" \
  --namespace="${NAMESPACE}" \
  --from-file=tls.crt="${CERT_DIR}/tls.crt" \
  --from-file=tls.key="${CERT_DIR}/tls.key" \
  --from-file=ca.crt="${CERT_DIR}/ca.crt" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "========================================="
echo "  TLS secret '${SECRET_NAME}' created"
echo "  in namespace '${NAMESPACE}'"
echo "========================================="
