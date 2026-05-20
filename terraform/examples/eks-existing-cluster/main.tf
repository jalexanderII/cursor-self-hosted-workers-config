terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
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

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context
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

variable "kubeconfig_path" {
  description = "Path to kubeconfig for the target cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Optional kubeconfig context. Leave null to use the current context."
  type        = string
  default     = null
  nullable    = true
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

variable "worker_image_tag" {
  description = "Worker image tag."
  type        = string
  default     = "latest"
}

variable "worker_image_override" {
  description = "Optional full image URI. If empty, the managed ECR repo and worker_image_tag are used."
  type        = string
  default     = ""
}

variable "cursor_api_secret_name" {
  description = "Secrets Manager secret name for the Cursor service account API key."
  type        = string
  default     = "cursor/self-hosted-workers/cursor-api-key"
}

variable "github_pat_secret_name" {
  description = "Secrets Manager secret name for the GitHub PAT."
  type        = string
  default     = "cursor/self-hosted-workers/github-pat"
}

variable "repo_env_secret_names" {
  description = "Optional AWS Secrets Manager secret containers for repo-local env/config files."
  type        = list(string)
  default     = []
}

variable "k8s_namespace" {
  description = "Kubernetes namespace."
  type        = string
  default     = "cursord"
}

variable "worker_deployment_name" {
  description = "WorkerDeployment name."
  type        = string
  default     = "cursor-workers"
}

variable "cursor_api_key_secret_name" {
  description = "Kubernetes secret name containing the Cursor API key."
  type        = string
  default     = "cursor-workers-api-key"
}

variable "github_pat_secret_name_k8s" {
  description = "Kubernetes secret name containing the GitHub PAT."
  type        = string
  default     = "cursor-workers-github"
}

variable "repo_env_secret_name_k8s" {
  description = "Optional Kubernetes secret name with repo env/config files."
  type        = string
  default     = ""
}

variable "repo_env_mappings" {
  description = "Optional comma-separated mounted-file:repo-target mappings."
  type        = string
  default     = ""
}

variable "repo_slug" {
  description = "Repository slug workers clone, for example owner/repo."
  type        = string
}

variable "repo_branch" {
  description = "Default branch."
  type        = string
  default     = "main"
}

variable "worker_pool_name" {
  description = "Cursor worker pool name."
  type        = string
}

variable "worker_ready_replicas" {
  description = "Idle ready worker floor."
  type        = number
  default     = 3
}

variable "worker_idle_release_timeout" {
  description = "Worker idle release timeout in seconds."
  type        = number
  default     = 900
}

variable "worker_labels" {
  description = "Cursor worker labels."
  type        = map(string)
  default = {
    env      = "prod"
    platform = "kubernetes"
  }
}

variable "request_cpu" {
  description = "Worker pod CPU request."
  type        = string
  default     = "1"
}

variable "request_memory" {
  description = "Worker pod memory request."
  type        = string
  default     = "2Gi"
}

variable "limit_cpu" {
  description = "Worker pod CPU limit."
  type        = string
  default     = "4"
}

variable "limit_memory" {
  description = "Worker pod memory limit."
  type        = string
  default     = "8Gi"
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

  worker_image = var.worker_image_override != "" ? var.worker_image_override : "${module.ecr.repository_url}:${var.worker_image_tag}"
  worker_labels_csv = join(",", [
    for key, value in var.worker_labels : "${key}=${value}"
  ])

  worker_manifest = templatefile("${path.module}/../../../kube/manifests/workers.tpl.yaml", {
    worker_deployment_name     = var.worker_deployment_name
    namespace                  = var.k8s_namespace
    cursor_api_key_secret_name = var.cursor_api_key_secret_name
    ready_replicas             = var.worker_ready_replicas
    app_label                  = var.worker_deployment_name
    worker_image               = local.worker_image
    repo_slug                  = jsonencode(var.repo_slug)
    repo_branch                = jsonencode(var.repo_branch)
    github_pat_secret_name     = var.github_pat_secret_name_k8s
    worker_pool_name           = jsonencode(var.worker_pool_name)
    idle_release_timeout       = var.worker_idle_release_timeout
    worker_labels_csv          = jsonencode(local.worker_labels_csv)
    repo_env_mappings          = var.repo_env_mappings == "" ? "" : jsonencode(var.repo_env_mappings)
    repo_env_secret_name       = var.repo_env_secret_name_k8s
    request_cpu                = jsonencode(var.request_cpu)
    request_memory             = jsonencode(var.request_memory)
    limit_cpu                  = jsonencode(var.limit_cpu)
    limit_memory               = jsonencode(var.limit_memory)
  })
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

module "secrets" {
  source = "../../modules/secrets-manager"

  cursor_api_secret_name = var.cursor_api_secret_name
  github_pat_secret_name = var.github_pat_secret_name
  repo_env_secret_names  = var.repo_env_secret_names
  tags                   = module.tags.tags
}

module "workers" {
  source = "../../modules/eks-workers"

  namespace                     = var.k8s_namespace
  worker_labels                 = var.worker_labels
  rendered_worker_manifest      = local.worker_manifest
  rendered_worker_manifest_path = "${path.module}/rendered/workers.yaml"
}

output "worker_image_repository_url" {
  description = "Build and push kube/worker-image to this ECR repository."
  value       = module.ecr.repository_url
}

output "cursor_api_secret_name" {
  description = "AWS secret to populate with make put-secret-cursor-api-key."
  value       = module.secrets.cursor_api_secret_name
}

output "github_pat_secret_name" {
  description = "AWS secret to populate with make put-secret-github-pat."
  value       = module.secrets.github_pat_secret_name
}

output "rendered_worker_manifest_path" {
  description = "Apply with make kube-apply-rendered after Kubernetes secrets exist."
  value       = module.workers.worker_manifest_path
}
