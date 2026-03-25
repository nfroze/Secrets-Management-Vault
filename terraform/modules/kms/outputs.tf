output "vault_unseal_key_id" {
  description = "KMS key ID for Vault auto-unseal"
  value       = aws_kms_key.vault_unseal.key_id
}

output "vault_unseal_key_arn" {
  description = "KMS key ARN for Vault auto-unseal"
  value       = aws_kms_key.vault_unseal.arn
}

output "rds_key_arn" {
  description = "KMS key ARN for RDS encryption"
  value       = aws_kms_key.rds.arn
}
