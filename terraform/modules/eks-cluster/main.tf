variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.35"
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to the Kubernetes API endpoint."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to the Kubernetes API endpoint."
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs permitted to access the public API endpoint when enabled."
  type        = list(string)
  default     = []
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Grant the Terraform caller cluster-admin. Keep false in production and use explicit access entries."
  type        = bool
  default     = false
}

variable "access_entries" {
  description = "Explicit EKS access entries for administrator and operator roles."
  type        = map(any)
  default     = {}
}

variable "cluster_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for Kubernetes secret envelope encryption."
  type        = string
  default     = null
  nullable    = true
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

variable "node_capacity_type" {
  description = "Managed node group capacity type."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_disk_size_gb" {
  description = "Root disk size for worker nodes."
  type        = number
  default     = 200
}

variable "node_labels" {
  description = "Labels applied to worker nodes."
  type        = map(string)
  default = {
    "cursor.com/workload" = "cloud-agent-worker"
  }
}

variable "node_taints" {
  description = "Taints applied to dedicated worker nodes."
  type        = map(any)
  default = {
    cursor_workers = {
      key    = "cursor.com/workload"
      value  = "cloud-agent-worker"
      effect = "NO_SCHEDULE"
    }
  }
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

check "endpoint_access_is_safe" {
  assert {
    condition     = !var.cluster_endpoint_public_access || length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "Public EKS API access requires at least one explicit restricted CIDR."
  }
}

check "administrator_access_exists" {
  assert {
    condition     = var.enable_cluster_creator_admin_permissions || length(var.access_entries) > 0
    error_message = "Configure at least one explicit EKS access entry before disabling cluster-creator admin."
  }
}

check "node_capacity_is_ordered" {
  assert {
    condition     = var.node_min_size <= var.node_desired_size && var.node_desired_size <= var.node_max_size
    error_message = "Node capacity must satisfy min_size <= desired_size <= max_size."
  }
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

  cluster_endpoint_private_access          = var.cluster_endpoint_private_access
  cluster_endpoint_public_access           = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  access_entries                           = var.access_entries
  authentication_mode                      = "API"
  enable_irsa                              = true
  cluster_enabled_log_types                = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days   = 90
  cluster_encryption_config = var.cluster_kms_key_arn == null ? null : {
    provider_key_arn = var.cluster_kms_key_arn
    resources        = ["secrets"]
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    cursor_workers = {
      min_size       = var.node_min_size
      desired_size   = var.node_desired_size
      max_size       = var.node_max_size
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type
      ami_type       = "AL2023_x86_64_STANDARD"
      disk_size      = var.node_disk_size_gb
      labels         = var.node_labels
      taints         = var.node_taints

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
        instance_metadata_tags      = "disabled"
      }

      update_config = {
        max_unavailable_percentage = 33
      }
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
