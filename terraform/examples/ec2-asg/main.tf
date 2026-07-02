terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
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

variable "vpc_id" {
  description = "VPC ID for the worker fleet. Production deployments must use an explicitly selected VPC."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the worker ASG. Use at least two availability zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two private subnets."
  }
}

variable "ec2_https_egress_cidr_blocks" {
  description = "CIDRs allowed on outbound TCP 443. Use a corporate egress proxy or firewall for FQDN enforcement."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "repo_url" {
  description = "HTTPS repository clone URL without embedded credentials."
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
  description = "Default branch workers reset to."
  type        = string
  default     = "main"
}

variable "scm_username" {
  description = "HTTPS SCM username for the credential helper."
  type        = string
  default     = "x-access-token"
}

variable "worker_pool_name" {
  description = "Cursor worker pool name."
  type        = string
}

variable "worker_idle_release_timeout" {
  description = "Worker idle release timeout in seconds."
  type        = number
  default     = 900
}

variable "cursor_api_secret_name" {
  description = "Secrets Manager secret name for the Cursor service account API key."
  type        = string
  default     = "cursor/self-hosted-workers/cursor-api-key"
}

variable "manage_aws_secret_containers" {
  description = "Create AWS Secrets Manager containers. Set false to reference enterprise-managed secrets."
  type        = bool
  default     = true
}

variable "existing_cursor_api_secret_arn" {
  description = "Existing Cursor API key secret ARN when manage_aws_secret_containers is false."
  type        = string
  default     = null
  nullable    = true
}

variable "existing_scm_token_secret_arn" {
  description = "Existing SCM token secret ARN when manage_aws_secret_containers is false."
  type        = string
  default     = null
  nullable    = true
}

variable "existing_repo_env_secret_arns" {
  description = "Existing repo environment secret ARNs when manage_aws_secret_containers is false."
  type        = list(string)
  default     = []
}

variable "scm_token_secret_name" {
  description = "Secrets Manager secret name for the HTTPS SCM token."
  type        = string
  default     = "cursor/self-hosted-workers/scm-token"
}

variable "secrets_kms_key_id" {
  description = "Optional customer-managed KMS key ARN for Secrets Manager and worker decrypt access."
  type        = string
  default     = null
  nullable    = true
}

variable "ec2_root_volume_kms_key_id" {
  description = "Optional customer-managed KMS key ID or ARN for worker root volumes."
  type        = string
  default     = null
  nullable    = true
}

variable "repo_env_secret_names" {
  description = "Optional repo-local env/config secret names."
  type        = list(string)
  default     = []
}

variable "repo_env_mappings" {
  description = "Optional mapping file body: repo-relative path followed by secret ID per line."
  type        = string
  default     = ""
}

variable "ec2_instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "m6i.xlarge"
}

variable "ec2_asg_min_size" {
  description = "ASG minimum size."
  type        = number
  default     = 1
}

variable "ec2_asg_desired_capacity" {
  description = "ASG desired capacity."
  type        = number
  default     = 1
}

variable "ec2_asg_max_size" {
  description = "ASG maximum size."
  type        = number
  default     = 3
}

variable "ec2_worker_slots_per_instance" {
  description = "Initial worker slots on each instance."
  type        = number
  default     = 1
}

variable "ec2_max_local_workers" {
  description = "Maximum worker slots local autoscaling may create on each instance."
  type        = number
  default     = 1
}

variable "ec2_associate_public_ip_address" {
  description = "Assign public IPs to worker instances."
  type        = bool
  default     = false
}

variable "ec2_ami_id" {
  description = "Reviewed AMI ID for worker instances."
  type        = string
}

variable "labels_json" {
  description = "Cursor labels JSON for EC2 workers."
  type        = string
  default     = <<-JSON
  {
    "env": "prod",
    "platform": "ec2"
  }
  JSON
}

module "tags" {
  source = "../../modules/common-tags"

  deployment_name = var.deployment_name
  environment     = var.environment
  extra_tags      = var.extra_tags
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = module.tags.tags
  }
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

check "cursor_worker_team_limit" {
  assert {
    condition     = var.ec2_asg_max_size * var.ec2_max_local_workers <= 50
    error_message = "Configured EC2 capacity exceeds Cursor's default 50-worker team limit. Obtain approval for a higher limit before increasing it."
  }
}

check "external_secret_arns_are_configured" {
  assert {
    condition = (
      var.manage_aws_secret_containers ||
      (var.existing_cursor_api_secret_arn != null && var.existing_scm_token_secret_arn != null)
    )
    error_message = "Existing Cursor API and SCM token secret ARNs are required when secret containers are externally managed."
  }
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

locals {
  cursor_api_secret_arn_effective = var.manage_aws_secret_containers ? module.secrets[0].cursor_api_secret_arn : var.existing_cursor_api_secret_arn
  scm_token_secret_arn_effective  = var.manage_aws_secret_containers ? module.secrets[0].scm_token_secret_arn : var.existing_scm_token_secret_arn
  repo_env_secret_arns_effective  = var.manage_aws_secret_containers ? module.secrets[0].repo_env_secret_arns : var.existing_repo_env_secret_arns
}

module "ec2_workers" {
  source = "../../modules/ec2-worker-asg"

  name_prefix                 = var.deployment_name
  aws_region                  = var.aws_region
  vpc_id                      = var.vpc_id
  subnet_ids                  = var.subnet_ids
  repo_url                    = var.repo_url
  repo_branch                 = var.repo_branch
  scm_username                = var.scm_username
  worker_pool_name            = var.worker_pool_name
  worker_idle_release_timeout = var.worker_idle_release_timeout
  worker_slots_per_instance   = var.ec2_worker_slots_per_instance
  max_local_workers           = var.ec2_max_local_workers
  instance_type               = var.ec2_instance_type
  ami_id                      = var.ec2_ami_id
  root_volume_kms_key_id      = var.ec2_root_volume_kms_key_id
  associate_public_ip_address = var.ec2_associate_public_ip_address
  https_egress_cidr_blocks    = var.ec2_https_egress_cidr_blocks
  dns_egress_cidr_blocks      = [data.aws_vpc.selected.cidr_block]
  asg_min_size                = var.ec2_asg_min_size
  asg_desired_capacity        = var.ec2_asg_desired_capacity
  asg_max_size                = var.ec2_asg_max_size
  cursor_api_secret_arn       = local.cursor_api_secret_arn_effective
  cursor_api_secret_name      = var.cursor_api_secret_name
  scm_token_secret_arn        = local.scm_token_secret_arn_effective
  scm_token_secret_name       = var.scm_token_secret_name
  repo_env_secret_arns        = local.repo_env_secret_arns_effective
  secrets_kms_key_arn         = var.secrets_kms_key_id
  repo_env_mappings           = var.repo_env_mappings
  labels_json                 = var.labels_json
  tags                        = module.tags.tags
}

module "observability" {
  source = "../../modules/ec2-observability"

  dashboard_name   = "${var.deployment_name}-ec2-workers"
  metric_namespace = "Cursor/SelfHostedWorkers"
  repo_metric_dimension = module.ec2_workers.repo_metric_dimension
}

output "autoscaling_group_name" {
  description = "EC2 worker Auto Scaling Group."
  value       = module.ec2_workers.autoscaling_group_name
}

output "worker_security_group_id" {
  description = "Worker security group."
  value       = module.ec2_workers.security_group_id
}

output "cursor_api_secret_name" {
  description = "Populate this secret with make put-secret-cursor-api-key."
  value       = var.cursor_api_secret_name
}

output "scm_token_secret_name" {
  description = "Populate this secret with the HTTPS SCM token."
  value       = var.scm_token_secret_name
}

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard for EC2 workers."
  value       = module.observability.dashboard_name
}

output "compressed_user_data_base64_length" {
  description = "Base64 gzip payload length; EC2 Launch Templates allow at most 21,848 characters."
  value       = module.ec2_workers.compressed_user_data_base64_length
}
