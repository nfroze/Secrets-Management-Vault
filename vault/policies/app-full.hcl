# =========================================================
# Policy: app-full
# Composite policy for the demo application.
# Grants access to all secrets engines: database (readwrite),
# AWS credentials, PKI certificates, and transit encryption.
# =========================================================

# Database — read-write dynamic credentials
path "database/creds/readwrite" {
  capabilities = ["read"]
}

path "database/creds/readonly" {
  capabilities = ["read"]
}

# AWS — dynamic IAM credentials
path "aws/creds/s3-readwrite" {
  capabilities = ["read"]
}

# PKI — certificate issuance
path "pki_int/issue/internal-service" {
  capabilities = ["create", "update"]
}

path "pki_int/cert/ca" {
  capabilities = ["read"]
}

# Transit — encryption as a service
path "transit/encrypt/app-data" {
  capabilities = ["update"]
}

path "transit/decrypt/app-data" {
  capabilities = ["update"]
}

path "transit/rewrap/app-data" {
  capabilities = ["update"]
}

path "transit/keys/app-data" {
  capabilities = ["read"]
}

# Lease management
path "sys/leases/renew" {
  capabilities = ["update"]
}

path "sys/leases/revoke" {
  capabilities = ["update"]
}
