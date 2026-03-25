########################################
# EKS Cluster
########################################

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-eks"
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.cluster.id]
  }

  encryption_config {
    resources = ["secrets"]

    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-eks"
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_cloudwatch_log_group.eks,
  ]
}

########################################
# EKS Managed Node Group
########################################

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    Environment = var.environment
    Project     = var.project_name
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-node-group"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
    aws_eks_addon.vpc_cni, # VPC CNI must be ready before nodes register
  ]
}

########################################
# EKS Add-ons
########################################

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.common_tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.common_tags

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.common_tags
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.common_tags

  depends_on = [aws_eks_node_group.main]
}

########################################
# Cluster Security Group
########################################

resource "aws_security_group" "cluster" {
  name_prefix = "${var.project_name}-eks-cluster-"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-eks-cluster-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "cluster_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
  description       = "Allow all outbound traffic"
}

########################################
# CloudWatch Log Group for EKS
########################################

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.project_name}-eks/cluster"
  retention_in_days = 30

  tags = var.common_tags
}

########################################
# KMS Key for EKS Secrets Encryption
########################################

resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for EKS secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  # EKS service needs explicit permissions for envelope encryption of K8s secrets
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
      },
      {
        Sid    = "AllowEKSService"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-eks-secrets-key"
  })
}

data "aws_caller_identity" "current" {}

########################################
# OIDC Provider for IRSA
########################################

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-eks-oidc"
  })
}
