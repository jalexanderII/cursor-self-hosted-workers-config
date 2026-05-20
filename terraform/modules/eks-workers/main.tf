variable "namespace" {
  description = "Kubernetes namespace for the Cursor controller and workers."
  type        = string
  default     = "cursord"
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

variable "worker_labels" {
  description = "Cursor worker labels rendered into a ConfigMap for reference."
  type        = map(string)
  default = {
    env      = "prod"
    platform = "kubernetes"
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
  }
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
    name  = "env.enableAuthManagement"
    value = "true"
  }

  set {
    name  = "rbac.singleNamespace"
    value = "true"
  }
}

resource "kubernetes_config_map_v1" "worker_labels" {
  metadata {
    name      = "cursor-worker-labels"
    namespace = kubernetes_namespace_v1.workers.metadata[0].name
  }

  data = {
    "labels.json" = jsonencode(var.worker_labels)
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

output "worker_manifest_path" {
  description = "Path to the rendered WorkerDeployment YAML."
  value       = local_file.worker_manifest.filename
}
