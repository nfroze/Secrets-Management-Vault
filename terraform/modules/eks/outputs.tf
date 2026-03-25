output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = aws_security_group.cluster.id
}

output "node_role_arn" {
  description = "IAM role ARN of the EKS node group"
  value       = aws_iam_role.node.arn
}

output "vault_iam_role_arn" {
  description = "IAM role ARN for Vault (IRSA)"
  value       = aws_iam_role.vault.arn
}

output "vault_iam_role_name" {
  description = "IAM role name for Vault (IRSA)"
  value       = aws_iam_role.vault.name
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL (without https://)"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}
