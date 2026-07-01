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

variable "manage_ecr_repository" {
  description = "Create the worker ECR repository. Set false to use an enterprise-managed registry."
  type        = bool
  default     = true
}

variable "existing_ecr_repository_url" {
  description = "Existing registry repository URL when manage_ecr_repository is false."
  type        = string
  default     = null
  nullable    = true
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

variable "secrets_kms_key_id" {
  description = "Optional customer-managed KMS key ID or ARN for Secrets Manager."
  type        = string
  default     = null
  nullable    = true
}

variable "worker_image_tag" {
  description = "Immutable worker image tag. Do not use latest for production."
  type        = string
  default     = "release-CHANGE_ME"

  validation {
    condition     = lower(var.worker_image_tag) != "latest" && trimspace(var.worker_image_tag) != ""
    error_message = "worker_image_tag must be a non-empty immutable tag and cannot be latest."
  }
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

variable "manage_aws_secret_containers" {
  description = "Create AWS Secrets Manager containers. Set false when the enterprise secret platform manages them."
  type        = bool
  default     = true
}

variable "scm_token_secret_name" {
  description = "Secrets Manager secret name for the HTTPS SCM token."
  type        = string
  default     = "cursor/self-hosted-workers/scm-token"
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

variable "pod_security_version" {
  description = "Pod Security Standards version matching the target Kubernetes minor, for example v1.35."
  type        = string
  default     = "latest"
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

variable "scm_token_secret_name_k8s" {
  description = "Kubernetes secret name containing the HTTPS SCM token."
  type        = string
  default     = "cursor-workers-scm"
}

variable "scm_token_secret_key" {
  description = "Key in the Kubernetes SCM token Secret."
  type        = string
  default     = "token"
}

variable "scm_username" {
  description = "HTTPS SCM username. Use x-access-token for GitHub tokens and oauth2 for GitLab tokens."
  type        = string
  default     = "x-access-token"
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

variable "repo_url" {
  description = "HTTPS repository clone URL."
  type        = string

  validation {
    condition = (
      can(regex("^https://[^/]+/.+", var.repo_url)) &&
      !can(regex("^https://[^/]*@", var.repo_url))
    )
    error_message = "repo_url must be an HTTPS clone URL without embedded credentials."
  }
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

variable "kubernetes_labels" {
  description = "Kubernetes labels used for operations and cost allocation. These are separate from Cursor worker labels."
  type        = map(string)
  default = {
    environment = "prod"
    service     = "cursor-agent-worker"
  }
}

variable "kubernetes_annotations" {
  description = "Additional annotations for worker pods."
  type        = map(string)
  default     = {}
}

variable "worker_service_account_annotations" {
  description = "Annotations for the worker ServiceAccount, such as IRSA metadata."
  type        = map(string)
  default     = {}
}

variable "worker_node_selector" {
  description = "Optional node selector for worker pods."
  type        = map(string)
  default     = {}
}

variable "worker_tolerations" {
  description = "Optional tolerations for dedicated worker node groups."
  type        = list(any)
  default     = []
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

variable "request_ephemeral_storage" {
  description = "Worker pod ephemeral-storage request."
  type        = string
  default     = "10Gi"
}

variable "limit_ephemeral_storage" {
  description = "Worker pod ephemeral-storage limit."
  type        = string
  default     = "100Gi"
}

variable "workspace_size_limit" {
  description = "Size limit for the ephemeral workspace volume."
  type        = string
  default     = "80Gi"
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

  worker_repository_url = var.manage_ecr_repository ? module.ecr[0].repository_url : var.existing_ecr_repository_url
  worker_image          = var.worker_image_override != "" ? var.worker_image_override : "${local.worker_repository_url}:${var.worker_image_tag}"
  worker_labels_csv = join(",", [
    for key, value in var.worker_labels : "${key}=${value}"
  ])

  worker_manifest = templatefile("${path.module}/../../../kube/manifests/workers.tpl.yaml", {
    worker_deployment_name           = var.worker_deployment_name
    namespace                        = var.k8s_namespace
    cursor_api_key_secret_name       = var.cursor_api_key_secret_name
    ready_replicas                   = var.worker_ready_replicas
    app_label                        = var.worker_deployment_name
    worker_image                     = local.worker_image
    image_pull_policy                = "IfNotPresent"
    repo_url                         = jsonencode(var.repo_url)
    repo_branch                      = jsonencode(var.repo_branch)
    scm_username                     = jsonencode(var.scm_username)
    scm_token_secret_name            = var.scm_token_secret_name_k8s
    scm_token_secret_key             = var.scm_token_secret_key
    worker_pool_name                 = jsonencode(var.worker_pool_name)
    idle_release_timeout             = var.worker_idle_release_timeout
    worker_labels_csv                = jsonencode(local.worker_labels_csv)
    repo_env_mappings                = var.repo_env_mappings == "" ? "" : jsonencode(var.repo_env_mappings)
    repo_env_secret_name             = var.repo_env_secret_name_k8s
    request_cpu                      = jsonencode(var.request_cpu)
    request_memory                   = jsonencode(var.request_memory)
    limit_cpu                        = jsonencode(var.limit_cpu)
    limit_memory                     = jsonencode(var.limit_memory)
    request_ephemeral_storage        = jsonencode(var.request_ephemeral_storage)
    limit_ephemeral_storage          = jsonencode(var.limit_ephemeral_storage)
    workspace_size_limit             = jsonencode(var.workspace_size_limit)
    worker_service_account_name      = "cursor-worker"
    termination_grace_period_seconds = 120
    kubernetes_labels                = var.kubernetes_labels
    kubernetes_annotations           = var.kubernetes_annotations
    node_selector_yaml               = length(var.worker_node_selector) == 0 ? "" : indent(8, yamlencode(var.worker_node_selector))
    tolerations_yaml                 = length(var.worker_tolerations) == 0 ? "" : indent(8, yamlencode(var.worker_tolerations))
  })
}

check "worker_registry_is_configured" {
  assert {
    condition     = var.worker_image_override != "" || var.manage_ecr_repository || var.existing_ecr_repository_url != null
    error_message = "Provide worker_image_override or existing_ecr_repository_url when ECR is externally managed."
  }
}

module "tags" {
  source = "../../modules/common-tags"

  deployment_name = var.deployment_name
  environment     = var.environment
  extra_tags      = var.extra_tags
}

module "ecr" {
  count  = var.manage_ecr_repository ? 1 : 0
  source = "../../modules/ecr-worker-image"

  repository_name      = var.ecr_repository_name
  image_tag_mutability = var.ecr_image_tag_mutability
  kms_key_arn          = var.ecr_kms_key_arn
  tags                 = module.tags.tags
}

module "secrets" {
  count  = var.manage_aws_secret_containers ? 1 : 0
  source = "../../modules/secrets-manager"

  cursor_api_secret_name = var.cursor_api_secret_name
  scm_token_secret_name  = var.scm_token_secret_name
  repo_env_secret_names  = var.repo_env_secret_names
  kms_key_id             = var.secrets_kms_key_id
  tags                   = module.tags.tags
}

module "workers" {
  source = "../../modules/eks-workers"

  namespace                          = var.k8s_namespace
  pod_security_version               = var.pod_security_version
  worker_app_label                   = var.worker_deployment_name
  worker_service_account_name        = "cursor-worker"
  worker_service_account_annotations = var.worker_service_account_annotations
  rendered_worker_manifest           = local.worker_manifest
  rendered_worker_manifest_path      = "${path.module}/rendered/workers.yaml"
}

output "worker_image_repository_url" {
  description = "Build and push kube/worker-image to this ECR repository."
  value       = local.worker_repository_url
}

output "cursor_api_secret_name" {
  description = "AWS secret to populate with make put-secret-cursor-api-key."
  value       = var.manage_aws_secret_containers ? module.secrets[0].cursor_api_secret_name : var.cursor_api_secret_name
}

output "scm_token_secret_name" {
  description = "AWS secret to populate with the SCM token."
  value       = var.manage_aws_secret_containers ? module.secrets[0].scm_token_secret_name : var.scm_token_secret_name
}

output "rendered_worker_manifest_path" {
  description = "Apply with make kube-apply-rendered after Kubernetes secrets exist."
  value       = module.workers.worker_manifest_path
}
