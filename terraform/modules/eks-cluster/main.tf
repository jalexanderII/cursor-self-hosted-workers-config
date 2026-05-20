variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "CIDR block for the worker VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for the VPC and node group."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway instead of one per AZ. Cheaper, less resilient."
  type        = bool
  default     = false
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["m6i.xlarge"]
}

variable "node_min_size" {
  description = "Minimum node group size."
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Desired node group size."
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum node group size."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags applied to EKS and VPC resources."
  type        = map(string)
  default     = {}
}

locals {
  public_subnets  = [for index, _ in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, index)]
  private_subnets = [for index, _ in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, index + 10)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = var.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true
  cluster_enabled_log_types                = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    cursor_workers = {
      min_size       = var.node_min_size
      desired_size   = var.node_desired_size
      max_size       = var.node_max_size
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = var.tags
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "vpc_id" {
  description = "Created VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets used by worker nodes."
  value       = module.vpc.private_subnets
}

output "update_kubeconfig_command" {
  description = "Command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${module.eks.cluster_name}"
}

data "aws_region" "current" {}
