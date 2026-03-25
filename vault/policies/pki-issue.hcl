# =========================================================
# Policy: pki-issue
# Grants certificate issuance from the intermediate CA.
# Used by services requesting TLS certificates for
# service-to-service communication.
# =========================================================

# Issue certificates from the intermediate CA
path "pki_int/issue/internal-service" {
  capabilities = ["create", "update"]
}

# Read CA certificate and CRL
path "pki_int/cert/ca" {
  capabilities = ["read"]
}

path "pki_int/ca/pem" {
  capabilities = ["read"]
}

path "pki_int/certs" {
  capabilities = ["list"]
}
