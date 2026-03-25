# =========================================================
# Policy: transit-encrypt
# Grants encrypt/decrypt access via the transit secrets
# engine. Applications send plaintext to Vault and receive
# ciphertext — encryption keys never leave Vault.
# =========================================================

# Encrypt data
path "transit/encrypt/app-data" {
  capabilities = ["update"]
}

# Decrypt data
path "transit/decrypt/app-data" {
  capabilities = ["update"]
}

# Rewrap data (re-encrypt with latest key version without exposing plaintext)
path "transit/rewrap/app-data" {
  capabilities = ["update"]
}

# Read key metadata (not the key itself)
path "transit/keys/app-data" {
  capabilities = ["read"]
}
