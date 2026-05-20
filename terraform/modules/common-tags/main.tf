variable "deployment_name" {
  description = "Stable deployment name used in tags and resource names."
  type        = string
}

variable "environment" {
  description = "Environment name, for example prod, staging, or dev."
  type        = string
}

variable "extra_tags" {
  description = "Additional tags to merge into every tagged resource."
  type        = map(string)
  default     = {}
}

locals {
  tags = merge(
    {
      Application = "cursor-self-hosted-cloud-agents"
      Deployment  = var.deployment_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.extra_tags
  )
}

output "tags" {
  description = "Common tags for this deployment."
  value       = local.tags
}
