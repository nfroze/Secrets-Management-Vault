# =========================================================
# Policy: aws-credentials
# Grants access to dynamic AWS IAM credentials via the
# AWS secrets engine. Scoped to the s3-readwrite role.
# =========================================================

# Generate dynamic AWS credentials
path "aws/creds/s3-readwrite" {
  capabilities = ["read"]
}

# Lease management
path "sys/leases/renew" {
  capabilities = ["update"]
}

path "sys/leases/revoke" {
  capabilities = ["update"]
}
