variable "repository_name" {
  description = "ECR repository name for the Kubernetes worker image."
  type        = string
}

variable "image_tag_mutability" {
  description = "ECR image tag mutability. IMMUTABLE is safer for production."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "force_delete" {
  description = "Whether Terraform can delete this repository even when it contains images."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN. When null, ECR uses AES256."
  type        = string
  default     = null
  nullable    = true
}

variable "lifecycle_keep_tagged_images" {
  description = "Number of tagged images to retain."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to ECR resources."
  type        = map(string)
  default     = {}
}

resource "aws_ecr_repository" "worker" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  encryption_configuration {
    encryption_type = var.kms_key_arn == null ? "AES256" : "KMS"
    kms_key         = var.kms_key_arn
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "worker" {
  repository = aws_ecr_repository.worker.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the most recent tagged worker images."
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release", "manual", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = var.lifecycle_keep_tagged_images
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 14 days."
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

output "repository_name" {
  description = "ECR repository name."
  value       = aws_ecr_repository.worker.name
}

output "repository_url" {
  description = "ECR repository URL."
  value       = aws_ecr_repository.worker.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN."
  value       = aws_ecr_repository.worker.arn
}
