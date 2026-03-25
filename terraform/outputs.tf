########################################
# VPC Outputs
########################################

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

########################################
# EKS Outputs
########################################

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  value       = module.eks.oidc_provider_arn
}

output "vault_iam_role_arn" {
  description = "Vault IAM role ARN (IRSA)"
  value       = module.eks.vault_iam_role_arn
}

########################################
# KMS Outputs
########################################

output "vault_kms_key_id" {
  description = "KMS key ID for Vault auto-unseal"
  value       = module.kms.vault_unseal_key_id
}

########################################
# RDS Outputs
########################################

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.endpoint
}

output "rds_address" {
  description = "RDS hostname"
  value       = module.rds.address
}

output "rds_db_name" {
  description = "Database name"
  value       = module.rds.db_name
}

output "rds_master_password" {
  description = "RDS master password (for Vault database engine configuration)"
  value       = module.rds.master_password
  sensitive   = true
}

########################################
# Kubeconfig Command
########################################

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
