terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Multi-team layout: one cluster-wide worker-set controller reconciles many
# per-team WorkerDeployments, each in its own namespace with its own pool,
# ServiceAccount, NetworkPolicy, ResourceQuota, and cost labels/tags.
#
# This is the pattern to use when a central platform team runs the controller
# and each product/team gets an isolated pool for chargeback and blast-radius
# separation. It maps directly to a namespace-per-team FinOps model
# (see docs/finops.md) and the isolation guidance in docs/security.md.
#
# This example intentionally does NOT manage ECR or AWS Secrets Manager. It
# assumes the worker image and per-team Kubernetes secrets already exist (image
# built/pushed by your pipeline; Cursor API key + SCM token created per team).
# See docs/aws-eks-existing-cluster.md for the secret-creation Make targets.

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

variable "pod_security_version" {
  description = "Pod Security Standards version matching the target Kubernetes minor, for example v1.35."
  type        = string
  default     = "latest"
}

variable "controller_namespace" {
  description = "Namespace for the shared, cluster-wide worker-set controller."
  type        = string
  default     = "cursord-system"
}

variable "controller_repository" {
  description = "OCI repository for Cursor's worker-set controller chart."
  type        = string
  default     = "oci://public.ecr.aws/j6w0t2f5/cursor"
}

variable "controller_chart" {
  description = "Cursor worker-set controller chart name."
  type        = string
  default     = "worker-set-controller-chart"
}

variable "controller_chart_version" {
  description = "Worker-set controller chart version."
  type        = string
  default     = "0.1.0-6c804a0"
}

variable "controller_image_tag" {
  description = "Worker-set controller image tag."
  type        = string
  default     = "6c804a0"
}

variable "controller_replicas" {
  description = "Controller replicas. Use at least 2 in production; leader election keeps one active."
  type        = number
  default     = 2
}

variable "worker_image" {
  description = "Full worker image URI (registry/repo:tag). Built and pushed by your pipeline. Do not use a mutable latest tag in production."
  type        = string

  validation {
    condition     = trimspace(var.worker_image) != "" && lower(var.worker_image) != "latest"
    error_message = "worker_image must be a real image reference, not empty or latest."
  }
}

variable "scm_username" {
  description = "HTTPS SCM username. Use x-access-token for GitHub tokens and oauth2 for GitLab tokens."
  type        = string
  default     = "x-access-token"
}

variable "worker_idle_release_timeout" {
  description = "Worker idle release timeout in seconds (applies to every team unless overridden per team)."
  type        = number
  default     = 900
}

variable "worker_node_selector" {
  description = "Node selector for worker pods. Set to {} for a shared node pool."
  type        = map(string)
  default     = {}
}

variable "worker_tolerations" {
  description = "Tolerations for worker pods. Set to [] for a shared node pool."
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

# One entry per team/chargeback domain. The map key is a short slug used to
# name the module instance and rendered manifest file.
variable "teams" {
  description = "Per-team worker pool definitions. Each team gets its own namespace, pool, and WorkerDeployment."
  type = map(object({
    namespace                  = string
    worker_pool_name           = string
    worker_deployment_name     = optional(string, "cursor-workers")
    repo_url                   = string
    repo_branch                = optional(string, "main")
    worker_ready_replicas      = optional(number, 3)
    cursor_api_key_secret_name = optional(string, "cursor-workers-api-key")
    scm_token_secret_name_k8s  = optional(string, "cursor-workers-scm")
    scm_token_secret_key       = optional(string, "token")
    # Cost-allocation dimensions. Mirror these onto AWS tags for the nodes that
    # run each namespace so FinOps can join on them (see docs/finops.md).
    cost_center = string
    owner       = string
  }))

  validation {
    condition = alltrue([
      for team in values(var.teams) :
      can(regex("^https://[^/]+/.+", team.repo_url)) && !can(regex("^https://[^/]*@", team.repo_url))
    ])
    error_message = "Each team's repo_url must be an HTTPS clone URL without embedded credentials."
  }
}

locals {
  # Render one WorkerDeployment manifest per team from the shared template.
  node_selector_yaml = (
    length(var.worker_node_selector) == 0
    ? ""
    : indent(8, chomp(yamlencode(var.worker_node_selector)))
  )
  tolerations_yaml = (
    length(var.worker_tolerations) == 0
    ? ""
    : indent(8, chomp(yamlencode(var.worker_tolerations)))
  )

  team_manifests = {
    for slug, team in var.teams :
    slug => templatefile("${path.module}/../../../kube/manifests/workers.tpl.yaml", {
      worker_deployment_name           = team.worker_deployment_name
      namespace                        = team.namespace
      cursor_api_key_secret_name       = team.cursor_api_key_secret_name
      ready_replicas                   = team.worker_ready_replicas
      app_label                        = team.worker_deployment_name
      worker_image                     = var.worker_image
      image_pull_policy                = "IfNotPresent"
      repo_url                         = jsonencode(team.repo_url)
      repo_branch                      = jsonencode(team.repo_branch)
      scm_username                     = jsonencode(var.scm_username)
      scm_token_secret_name            = team.scm_token_secret_name_k8s
      scm_token_secret_key             = team.scm_token_secret_key
      worker_pool_name                 = jsonencode(team.worker_pool_name)
      idle_release_timeout             = var.worker_idle_release_timeout
      worker_labels_csv                = jsonencode("team=${slug},pool=${team.worker_pool_name}")
      repo_env_mappings                = ""
      repo_env_secret_name             = ""
      request_cpu                      = jsonencode(var.request_cpu)
      request_memory                   = jsonencode(var.request_memory)
      limit_cpu                        = jsonencode(var.limit_cpu)
      limit_memory                     = jsonencode(var.limit_memory)
      request_ephemeral_storage        = jsonencode(var.request_ephemeral_storage)
      limit_ephemeral_storage          = jsonencode(var.limit_ephemeral_storage)
      workspace_size_limit             = jsonencode(var.workspace_size_limit)
      worker_service_account_name      = "cursor-worker"
      termination_grace_period_seconds = 120
      # Cost/ownership labels land on every worker pod for this team.
      kubernetes_labels = {
        service     = "cursor-agent-worker"
        team        = slug
        cost-center = team.cost_center
        owner       = team.owner
      }
      kubernetes_annotations = {}
      node_selector_yaml     = local.node_selector_yaml
      tolerations_yaml       = local.tolerations_yaml
    })
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

# ---------------------------------------------------------------------------
# One cluster-wide controller for the whole cluster. It watches every
# namespace, so each team's WorkerDeployment below is reconciled by this single
# controller. The WorkerDeployment CRD is cluster-scoped and installed once here.
# ---------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "controller" {
  metadata {
    name = var.controller_namespace
    labels = {
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = var.pod_security_version
    }
  }
}

resource "helm_release" "controller" {
  name       = "worker-set-controller"
  repository = var.controller_repository
  chart      = var.controller_chart
  namespace  = kubernetes_namespace_v1.controller.metadata[0].name
  version    = var.controller_chart_version

  set {
    name  = "imageTag"
    value = var.controller_image_tag
  }

  set {
    name  = "replicaCount"
    value = tostring(var.controller_replicas)
  }

  # Required so spec.auth (API-key -> short-lived token exchange) works.
  set {
    name  = "env.enableAuthManagement"
    value = "true"
  }

  # Cluster-wide: watch WorkerDeployments in all namespaces.
  set {
    name  = "rbac.singleNamespace"
    value = "false"
  }

  # Install the cluster-scoped CRD once from the shared controller.
  set {
    name  = "crd.install"
    value = "true"
  }

  set {
    name  = "podDisruptionBudget.enabled"
    value = "true"
  }

  set {
    name  = "podDisruptionBudget.minAvailable"
    value = "1"
  }
}

# ---------------------------------------------------------------------------
# One isolated worker pool per team. install_controller = false because the
# shared controller above reconciles all of these namespaces. controller_install_crd
# is irrelevant here since no controller/CRD is installed by the module call.
# ---------------------------------------------------------------------------
module "team_workers" {
  source   = "../../modules/eks-workers"
  for_each = var.teams

  install_controller = false

  namespace                     = each.value.namespace
  pod_security_version          = var.pod_security_version
  worker_app_label              = each.value.worker_deployment_name
  worker_service_account_name   = "cursor-worker"
  rendered_worker_manifest      = local.team_manifests[each.key]
  rendered_worker_manifest_path = "${path.module}/rendered/${each.key}-workers.yaml"

  namespace_labels = {
    team          = each.key
    "cost-center" = each.value.cost_center
  }

  # Ensure the CRD exists before per-team WorkerDeployments are applied.
  depends_on = [helm_release.controller]
}

output "controller_namespace" {
  description = "Namespace running the shared cluster-wide controller."
  value       = kubernetes_namespace_v1.controller.metadata[0].name
}

output "team_manifest_paths" {
  description = "Rendered WorkerDeployment manifests per team. Create each team's Kubernetes secrets, then apply these."
  value       = { for slug, mod in module.team_workers : slug => mod.worker_manifest_path }
}
