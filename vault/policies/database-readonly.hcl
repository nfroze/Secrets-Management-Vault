# =========================================================
# Policy: database-readonly
# Grants read access to dynamic database credentials
# Used by application workloads consuming Vault-managed
# PostgreSQL credentials via the database secrets engine.
# =========================================================

# Generate dynamic database credentials
path "database/creds/readonly" {
  capabilities = ["read"]
}

# Allow leases to be renewed (credential lifetime extension)
path "sys/leases/renew" {
  capabilities = ["update"]
}

# Allow leases to be revoked (clean shutdown)
path "sys/leases/revoke" {
  capabilities = ["update"]
}
