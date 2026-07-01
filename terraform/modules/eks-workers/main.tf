variable "namespace" {
  description = "Kubernetes namespace for the Cursor controller and workers."
  type        = string
  default     = "cursord"
}

variable "namespace_labels" {
  description = "Additional labels applied to the worker namespace."
  type        = map(string)
  default     = {}
}

variable "pod_security_version" {
  description = "Kubernetes Pod Security Standards version label. Pin this to the target cluster minor version in production."
  type        = string
  default     = "latest"
}

variable "controller_release_name" {
  description = "Helm release name for the Cursor worker-set controller."
  type        = string
  default     = "worker-set-controller"
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
  description = "Number of controller replicas. Leader election keeps one active."
  type        = number
  default     = 2

  validation {
    condition     = var.controller_replicas >= 2
    error_message = "controller_replicas must be at least 2 for the production reference."
  }
}

variable "controller_install_crd" {
  description = "Install the cluster-scoped WorkerDeployment CRD. Set false when the platform team manages it separately."
  type        = bool
  default     = true
}

variable "controller_service_monitor_enabled" {
  description = "Create the controller ServiceMonitor when Prometheus Operator is installed."
  type        = bool
  default     = false
}

variable "worker_service_account_name" {
  description = "Kubernetes ServiceAccount used by worker pods."
  type        = string
  default     = "cursor-worker"
}

variable "worker_service_account_annotations" {
  description = "Annotations for the worker ServiceAccount, such as IRSA or EKS Pod Identity integration metadata."
  type        = map(string)
  default     = {}
}

variable "worker_app_label" {
  description = "Value of the app label used to select worker pods."
  type        = string
  default     = "cursor-workers"
}

variable "enable_network_policy" {
  description = "Apply a portable worker NetworkPolicy allowing DNS and outbound HTTPS while denying inbound traffic."
  type        = bool
  default     = true
}

variable "enable_resource_quota" {
  description = "Apply a namespace ResourceQuota as a safety ceiling."
  type        = bool
  default     = true
}

variable "resource_quota_hard" {
  description = "Hard limits for the worker namespace. Size this above peak busy workers plus the idle floor."
  type        = map(string)
  default = {
    pods                         = "100"
    "requests.cpu"               = "100"
    "requests.memory"            = "200Gi"
    "requests.ephemeral-storage" = "2Ti"
    "limits.cpu"                 = "400"
    "limits.memory"              = "800Gi"
    "limits.ephemeral-storage"   = "5Ti"
  }
}

variable "rendered_worker_manifest" {
  description = "Rendered WorkerDeployment YAML. It is written locally and applied separately."
  type        = string
}

variable "rendered_worker_manifest_path" {
  description = "Local path where Terraform writes the rendered WorkerDeployment YAML."
  type        = string
}

variable "tags" {
  description = "Tags for Helm metadata where supported."
  type        = map(string)
  default     = {}
}

resource "kubernetes_namespace_v1" "workers" {
  metadata {
    name = var.namespace
    labels = merge(
      {
        "app.kubernetes.io/name"                     = "cursor-self-hosted-workers"
        "app.kubernetes.io/part-of"                  = "cursor-self-hosted-cloud-agents"
        "pod-security.kubernetes.io/enforce"         = "restricted"
        "pod-security.kubernetes.io/enforce-version" = var.pod_security_version
        "pod-security.kubernetes.io/audit"           = "restricted"
        "pod-security.kubernetes.io/audit-version"   = var.pod_security_version
        "pod-security.kubernetes.io/warn"            = "restricted"
        "pod-security.kubernetes.io/warn-version"    = var.pod_security_version
      },
      var.namespace_labels
    )
  }
}

resource "kubernetes_service_account_v1" "worker" {
  metadata {
    name        = var.worker_service_account_name
    namespace   = kubernetes_namespace_v1.workers.metadata[0].name
    annotations = var.worker_service_account_annotations
    labels = {
      "app.kubernetes.io/name"    = "cursor-self-hosted-worker"
      "app.kubernetes.io/part-of" = "cursor-self-hosted-cloud-agents"
    }
  }

  automount_service_account_token = false
}

resource "helm_release" "controller" {
  name       = var.controller_release_name
  repository = var.controller_repository
  chart      = var.controller_chart
  namespace  = kubernetes_namespace_v1.workers.metadata[0].name
  version    = var.controller_chart_version

  set {
    name  = "imageTag"
    value = var.controller_image_tag
  }

  set {
    name  = "replicaCount"
    value = tostring(var.controller_replicas)
  }

  set {
    name  = "env.enableAuthManagement"
    value = "true"
  }

  set {
    name  = "rbac.singleNamespace"
    value = "true"
  }

  set {
    name  = "crd.install"
    value = tostring(var.controller_install_crd)
  }

  set {
    name  = "podDisruptionBudget.enabled"
    value = "true"
  }

  set {
    name  = "podDisruptionBudget.minAvailable"
    value = "1"
  }

  set {
    name  = "metrics.serviceMonitor.enabled"
    value = tostring(var.controller_service_monitor_enabled)
  }
}

resource "kubernetes_network_policy_v1" "worker" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "cursor-worker-baseline"
    namespace = kubernetes_namespace_v1.workers.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = var.worker_app_label
      }
    }

    policy_types = ["Ingress", "Egress"]

    # Kubelet probes originate outside the pod namespace on many CNIs. Permit
    # only the worker management port; no other inbound ports are exposed.
    ingress {
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }

        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }

      ports {
        port     = "53"
        protocol = "UDP"
      }

      ports {
        port     = "53"
        protocol = "TCP"
      }
    }

    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }

      ports {
        port     = "443"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_resource_quota_v1" "workers" {
  count = var.enable_resource_quota ? 1 : 0

  metadata {
    name      = "cursor-worker-capacity"
    namespace = kubernetes_namespace_v1.workers.metadata[0].name
  }

  spec {
    hard = var.resource_quota_hard
  }
}

resource "local_file" "worker_manifest" {
  filename        = var.rendered_worker_manifest_path
  content         = var.rendered_worker_manifest
  file_permission = "0644"
}

output "namespace" {
  description = "Kubernetes namespace for workers."
  value       = kubernetes_namespace_v1.workers.metadata[0].name
}

output "controller_release_name" {
  description = "Helm release name."
  value       = helm_release.controller.name
}

output "worker_service_account_name" {
  description = "Kubernetes ServiceAccount used by worker pods."
  value       = kubernetes_service_account_v1.worker.metadata[0].name
}

output "worker_manifest_path" {
  description = "Path to the rendered WorkerDeployment YAML."
  value       = local_file.worker_manifest.filename
}
