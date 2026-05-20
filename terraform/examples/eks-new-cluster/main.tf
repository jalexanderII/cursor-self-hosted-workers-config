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
  default     = "1.30"
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
  default     = "MUTABLE"
}

locals {
  common_tags = merge(
    {
      Application = "cursor-self-hosted-cloud-agents"
      Deployment  = var.deployment_name
      Environment = var.environment
      ManagedBy   = "terraform"
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
  tags                 = module.tags.tags
}

module "cluster" {
  source = "../../modules/eks-cluster"

  cluster_name        = var.eks_cluster_name
  cluster_version     = var.eks_cluster_version
  vpc_cidr            = var.eks_vpc_cidr
  availability_zones  = slice(data.aws_availability_zones.available.names, 0, 3)
  single_nat_gateway  = var.eks_single_nat_gateway
  node_instance_types = var.eks_node_instance_types
  node_min_size       = var.eks_node_min_size
  node_desired_size   = var.eks_node_desired_size
  node_max_size       = var.eks_node_max_size
  tags                = module.tags.tags
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
