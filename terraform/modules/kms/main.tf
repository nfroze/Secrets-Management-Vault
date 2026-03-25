########################################
# KMS Key — Vault Auto-Unseal
# Access granted to Vault via IAM policy (IRSA) in the EKS module.
# Key policy uses root account access to avoid circular dependencies.
########################################

resource "aws_kms_key" "vault_unseal" {
  description             = "KMS key for HashiCorp Vault auto-unseal"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  key_usage               = "ENCRYPT_DECRYPT"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vault-unseal-key"
  })
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${var.project_name}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

########################################
# KMS Key — RDS Encryption
########################################

resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS storage encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rds-encryption-key"
  })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-rds-encryption"
  target_key_id = aws_kms_key.rds.key_id
}

########################################
# Data Sources
########################################

data "aws_caller_identity" "current" {}
