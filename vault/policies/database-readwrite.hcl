# =========================================================
# Policy: database-readwrite
# Grants read/write database credentials for services that
# need INSERT/UPDATE/DELETE access (e.g., API tier).
# =========================================================

# Generate dynamic database credentials (read-write role)
path "database/creds/readwrite" {
  capabilities = ["read"]
}

# Also allow readonly role access (principle of least privilege per request)
path "database/creds/readonly" {
  capabilities = ["read"]
}

# Lease management
path "sys/leases/renew" {
  capabilities = ["update"]
}

path "sys/leases/revoke" {
  capabilities = ["update"]
}
