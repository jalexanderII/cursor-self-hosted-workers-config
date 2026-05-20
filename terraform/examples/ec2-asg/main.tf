terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
  description = "Optional VPC ID. Defaults to the account default VPC."
  type        = string
  default     = null
  nullable    = true
}

variable "subnet_ids" {
  description = "Subnets for the worker ASG. Defaults to all default VPC subnets."
  type        = list(string)
  default     = []
}

variable "repo_slug" {
  description = "Repository slug workers clone, for example owner/repo."
  type        = string
}

variable "repo_branch" {
  description = "Default branch workers reset to."
  type        = string
  default     = "main"
}

variable "github_host" {
  description = "Git host."
  type        = string
  default     = "github.com"
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

variable "github_pat_secret_name" {
  description = "Secrets Manager secret name for the GitHub PAT."
  type        = string
  default     = "cursor/self-hosted-workers/github-pat"
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
  default     = 5
}

variable "ec2_max_local_workers" {
  description = "Maximum worker slots local autoscaling may create on each instance."
  type        = number
  default     = 15
}

variable "ec2_associate_public_ip_address" {
  description = "Assign public IPs to worker instances."
  type        = bool
  default     = false
}

variable "ec2_ami_id" {
  description = "Optional AMI override."
  type        = string
  default     = null
  nullable    = true
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

data "aws_vpc" "default" {
  count   = var.vpc_id == null ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
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
  vpc_id     = var.vpc_id == null ? data.aws_vpc.default[0].id : var.vpc_id
  subnet_ids = length(var.subnet_ids) == 0 ? data.aws_subnets.default[0].ids : var.subnet_ids
}

module "tags" {
  source = "../../modules/common-tags"

  deployment_name = var.deployment_name
  environment     = var.environment
  extra_tags      = var.extra_tags
}

module "secrets" {
  source = "../../modules/secrets-manager"

  cursor_api_secret_name = var.cursor_api_secret_name
  github_pat_secret_name = var.github_pat_secret_name
  repo_env_secret_names  = var.repo_env_secret_names
  tags                   = module.tags.tags
}

module "ec2_workers" {
  source = "../../modules/ec2-worker-asg"

  name_prefix                 = var.deployment_name
  aws_region                  = var.aws_region
  vpc_id                      = local.vpc_id
  subnet_ids                  = local.subnet_ids
  repo_slug                   = var.repo_slug
  repo_branch                 = var.repo_branch
  github_host                 = var.github_host
  worker_pool_name            = var.worker_pool_name
  worker_idle_release_timeout = var.worker_idle_release_timeout
  worker_slots_per_instance   = var.ec2_worker_slots_per_instance
  max_local_workers           = var.ec2_max_local_workers
  instance_type               = var.ec2_instance_type
  ami_id                      = var.ec2_ami_id
  associate_public_ip_address = var.ec2_associate_public_ip_address
  asg_min_size                = var.ec2_asg_min_size
  asg_desired_capacity        = var.ec2_asg_desired_capacity
  asg_max_size                = var.ec2_asg_max_size
  cursor_api_secret_arn       = module.secrets.cursor_api_secret_arn
  cursor_api_secret_name      = module.secrets.cursor_api_secret_name
  github_pat_secret_arn       = module.secrets.github_pat_secret_arn
  github_pat_secret_name      = module.secrets.github_pat_secret_name
  repo_env_secret_arns        = module.secrets.repo_env_secret_arns
  repo_env_mappings           = var.repo_env_mappings
  labels_json                 = var.labels_json
  tags                        = module.tags.tags
}

module "observability" {
  source = "../../modules/ec2-observability"

  dashboard_name   = "${var.deployment_name}-ec2-workers"
  metric_namespace = "Cursor/SelfHostedWorkers"
  repo_slug        = var.repo_slug
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
  value       = module.secrets.cursor_api_secret_name
}

output "github_pat_secret_name" {
  description = "Populate this secret with make put-secret-github-pat."
  value       = module.secrets.github_pat_secret_name
}

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard for EC2 workers."
  value       = module.observability.dashboard_name
}
