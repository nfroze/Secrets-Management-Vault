variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
}

variable "allocated_storage" {
  description = "Storage in GB"
  type        = number
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "master_username" {
  description = "Master username"
  type        = string
}

variable "db_subnet_group_name" {
  description = "DB subnet group name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "eks_security_group_id" {
  description = "Security group ID of the EKS cluster"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for storage encryption"
  type        = string
}

variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
