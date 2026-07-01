terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = local.common_tags
  }
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional local AWS profile for Terraform runs."
  type        = string
  default     = ""
}

variable "deployment_name" {
  description = "Stable deployment name."
  type        = string
  default     = "cursor-workers"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "prod"
}

variable "extra_tags" {
  description = "Additional resource tags."
  type        = map(string)
  default     = {}
}

variable "eks_cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "cursor-workers"
}

variable "eks_cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.35"
}

variable "eks_admin_principal_arn" {
  description = "IAM role ARN granted cluster-admin through an explicit EKS access entry."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.eks_admin_principal_arn))
    error_message = "eks_admin_principal_arn must be an IAM role ARN."
  }
}

variable "eks_cluster_endpoint_public_access" {
  description = "Enable the public Kubernetes API endpoint. Production defaults to private-only."
  type        = bool
  default     = false
}

variable "eks_cluster_endpoint_public_access_cidrs" {
  description = "Restricted CIDRs allowed to reach the public API endpoint."
  type        = list(string)
  default     = []
}

variable "eks_vpc_cidr" {
  description = "CIDR block for the EKS VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "eks_single_nat_gateway" {
  description = "Use one NAT gateway. Cheaper, less resilient than one NAT per AZ."
  type        = bool
  default     = false
}

variable "eks_node_instance_types" {
  description = "Managed node group instance types."
  type        = list(string)
  default     = ["m6i.xlarge"]
}

variable "eks_node_min_size" {
  description = "Minimum node group size."
  type        = number
  default     = 2
}

variable "eks_node_desired_size" {
  description = "Desired node group size."
  type        = number
  default     = 3
}

variable "eks_node_max_size" {
  description = "Maximum node group size."
  type        = number
  default     = 10
}

variable "ecr_repository_name" {
  description = "ECR repository for the worker image."
  type        = string
  default     = "cursor-self-hosted-worker"
}

variable "ecr_image_tag_mutability" {
  description = "ECR tag mutability. Use IMMUTABLE with unique worker image tags in stricter production flows."
  type        = string
  default     = "IMMUTABLE"
}

variable "ecr_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for ECR encryption."
  type        = string
  default     = null
  nullable    = true
}

variable "eks_cluster_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for Kubernetes secret envelope encryption."
  type        = string
  default     = null
  nullable    = true
}

locals {
  common_tags = merge(
    {
      Application = "cursor-self-hosted-cloud-agents"
      Deployment  = var.deployment_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Service     = "cursor-agent-worker"
      Platform    = "cursor"
    },
    var.extra_tags
  )
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "tags" {
  source = "../../modules/common-tags"

  deployment_name = var.deployment_name
  environment     = var.environment
  extra_tags      = var.extra_tags
}

module "ecr" {
  source = "../../modules/ecr-worker-image"

  repository_name      = var.ecr_repository_name
  image_tag_mutability = var.ecr_image_tag_mutability
  kms_key_arn          = var.ecr_kms_key_arn
  tags                 = module.tags.tags
}

module "cluster" {
  source = "../../modules/eks-cluster"

  cluster_name                             = var.eks_cluster_name
  cluster_version                          = var.eks_cluster_version
  vpc_cidr                                 = var.eks_vpc_cidr
  availability_zones                       = slice(data.aws_availability_zones.available.names, 0, 3)
  single_nat_gateway                       = var.eks_single_nat_gateway
  node_instance_types                      = var.eks_node_instance_types
  node_min_size                            = var.eks_node_min_size
  node_desired_size                        = var.eks_node_desired_size
  node_max_size                            = var.eks_node_max_size
  cluster_endpoint_private_access          = true
  cluster_endpoint_public_access           = var.eks_cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs     = var.eks_cluster_endpoint_public_access_cidrs
  enable_cluster_creator_admin_permissions = false
  cluster_kms_key_arn                      = var.eks_cluster_kms_key_arn
  access_entries = {
    administrator = {
      principal_arn = var.eks_admin_principal_arn
      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
  tags = module.tags.tags
}

output "cluster_name" {
  description = "Created EKS cluster."
  value       = module.cluster.cluster_name
}

output "update_kubeconfig_command" {
  description = "Run this before using the eks-existing-cluster example."
  value       = var.aws_profile != "" ? "aws eks update-kubeconfig --profile ${var.aws_profile} --region ${var.aws_region} --name ${module.cluster.cluster_name}" : "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.cluster.cluster_name}"
}

output "worker_image_repository_url" {
  description = "Build and push kube/worker-image to this ECR repository."
  value       = module.ecr.repository_url
}

output "vpc_id" {
  description = "Created VPC ID."
  value       = module.cluster.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets used by worker nodes."
  value       = module.cluster.private_subnet_ids
}
