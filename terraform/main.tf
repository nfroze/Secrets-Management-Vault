########################################
# VPC
########################################

module "vpc" {
  source = "./modules/vpc"

  project_name          = var.project_name
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  common_tags           = var.common_tags
}

########################################
# EKS
########################################

module "eks" {
  source = "./modules/eks"

  project_name        = var.project_name
  environment         = var.environment
  cluster_version     = var.eks_cluster_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  node_instance_types = var.eks_node_instance_types
  node_desired_size   = var.eks_node_desired_size
  node_min_size       = var.eks_node_min_size
  node_max_size       = var.eks_node_max_size
  kms_key_arn         = module.kms.vault_unseal_key_arn
  common_tags         = var.common_tags
}

########################################
# KMS
########################################

module "kms" {
  source = "./modules/kms"

  project_name = var.project_name
  common_tags  = var.common_tags
}

########################################
# RDS (PostgreSQL)
########################################

module "rds" {
  source = "./modules/rds"

  project_name          = var.project_name
  instance_class        = var.db_instance_class
  engine_version        = var.db_engine_version
  allocated_storage     = var.db_allocated_storage
  db_name               = var.db_name
  master_username       = var.db_master_username
  db_subnet_group_name  = module.vpc.database_subnet_group_name
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = module.vpc.vpc_cidr_block
  eks_security_group_id = module.eks.cluster_security_group_id
  kms_key_arn           = module.kms.rds_key_arn
  common_tags           = var.common_tags
}
