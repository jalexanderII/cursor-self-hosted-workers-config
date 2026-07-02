variable "name_prefix" {
  description = "Name prefix for EC2 worker resources."
  type        = string
}

variable "aws_region" {
  description = "AWS region where workers run."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for worker instances."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the Auto Scaling Group. Prefer private subnets with NAT egress."
  type        = list(string)
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
  description = "Default branch workers reset to before registration."
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
  description = "Idle release timeout in seconds."
  type        = number
  default     = 900
}

variable "worker_user" {
  description = "Linux user that owns worker processes and checkouts."
  type        = string
  default     = "ubuntu"
}

variable "worker_slots_per_instance" {
  description = "Initial worker slots per EC2 instance."
  type        = number
  default     = 1
}

variable "max_local_workers" {
  description = "Maximum worker slots that local autoscaling may create on one instance."
  type        = number
  default     = 1
}

variable "autoscale_min_idle" {
  description = "Minimum idle workers to keep available per instance."
  type        = number
  default     = 1
}

variable "autoscale_scale_step" {
  description = "Worker slots added per local scale-up."
  type        = number
  default     = 1
}

variable "autoscale_scale_down_step" {
  description = "Worker slots removed per local scale-down."
  type        = number
  default     = 1
}

variable "autoscale_scale_down_idle_seconds" {
  description = "How long extra idle workers must remain idle before removal."
  type        = number
  default     = 3600
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "m6i.xlarge"
}

variable "ami_id" {
  description = "Reviewed AMI ID for worker instances. Do not use account-wide latest-AMI lookups in production."
  type        = string
}

variable "cursor_install_url" {
  description = "Cursor CLI installer URL. Override with a reviewed internal mirror when required."
  type        = string
  default     = "https://cursor.com/install"

  validation {
    condition     = can(regex("^https://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+$", var.cursor_install_url))
    error_message = "cursor_install_url must be an HTTPS URL without quotes or whitespace."
  }
}

variable "associate_public_ip_address" {
  description = "Whether to assign public IPs. Prefer false for private subnets with NAT."
  type        = bool
  default     = false
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 100
}

variable "root_volume_type" {
  description = "Root EBS volume type."
  type        = string
  default     = "gp3"
}

variable "root_volume_kms_key_id" {
  description = "Optional customer-managed KMS key ID or ARN for root EBS encryption."
  type        = string
  default     = null
  nullable    = true
}

variable "asg_min_size" {
  description = "Minimum ASG size."
  type        = number
  default     = 1
}

variable "asg_desired_capacity" {
  description = "Desired ASG capacity."
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum ASG size."
  type        = number
  default     = 3
}

variable "cursor_api_secret_arn" {
  description = "ARN of the Cursor API key secret."
  type        = string
}

variable "cursor_api_secret_name" {
  description = "Name or ID of the Cursor API key secret."
  type        = string
}

variable "scm_token_secret_arn" {
  description = "ARN of the HTTPS SCM token secret."
  type        = string
}

variable "scm_token_secret_name" {
  description = "Name or ID of the HTTPS SCM token secret."
  type        = string
}

variable "repo_env_secret_arns" {
  description = "Optional repo-local env/config secret ARNs."
  type        = list(string)
  default     = []
}

variable "secrets_kms_key_arn" {
  description = "Optional customer-managed KMS key ARN used by worker Secrets Manager secrets."
  type        = string
  default     = null
  nullable    = true
}

variable "repo_env_mappings" {
  description = "Optional lines mapping repo-relative paths to Secrets Manager secret IDs."
  type        = string
  default     = ""
}

variable "labels_json" {
  description = "Cursor worker labels JSON."
  type        = string
  default     = <<-JSON
  {
    "env": "prod",
    "platform": "ec2"
  }
  JSON
}

variable "metric_namespace" {
  description = "CloudWatch namespace used by the EC2 metrics publisher."
  type        = string
  default     = "Cursor/SelfHostedWorkers"
}

variable "https_egress_cidr_blocks" {
  description = "CIDR blocks allowed for outbound HTTPS. Security groups cannot enforce FQDN restrictions."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "dns_egress_cidr_blocks" {
  description = "CIDR blocks allowed for DNS. Prefer the VPC resolver/network rather than internet-wide DNS."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to EC2 resources."
  type        = map(string)
  default     = {}
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  base_dir = "/opt/cursor-workers/base"

  # Derive host and path from repo_url so operators only set one field.
  repo_url_normalized = trimsuffix(var.repo_url, "/")
  repo_url_base = endswith(local.repo_url_normalized, ".git") ? trimsuffix(local.repo_url_normalized, ".git") : local.repo_url_normalized
  repo_without_scheme = replace(local.repo_url_base, "https://", "")
  repo_host           = split("/", local.repo_without_scheme)[0]
  repo_path = join(
    "/",
    slice(
      split("/", local.repo_without_scheme),
      1,
      length(split("/", local.repo_without_scheme))
    )
  )

  workers = [
    for index in range(var.worker_slots_per_instance) : {
      id              = tostring(index + 1)
      name            = "ec2-{INSTANCE_ID}-worker-${index + 1}"
      worker_dir      = index == 0 ? local.base_dir : "/opt/cursor-workers/worker-${index + 1}"
      management_port = 8080 + index
      worktree        = index == 0 ? false : true
    }
  ]

  workers_json = templatefile("${path.module}/../../templates/workers-json.tftpl", {
    repo_url    = var.repo_url
    repo_branch = var.repo_branch
    workers     = local.workers
  })

  env_file = join("\n", compact([
    "AWS_REGION=${var.aws_region}",
    "CURSOR_API_SECRET_ID=${var.cursor_api_secret_name}",
    "SCM_TOKEN_SECRET_ID=${var.scm_token_secret_name}",
    "SCM_HOST=${local.repo_host}",
    "SCM_USERNAME=${var.scm_username}",
    "CURSOR_WORKER_POOL_NAME=${var.worker_pool_name}",
    "CURSOR_WORKER_IDLE_RELEASE_TIMEOUT=${var.worker_idle_release_timeout}",
    "CURSOR_WORKER_USER=${var.worker_user}",
    "CURSOR_AGENT_BIN=/home/${var.worker_user}/.local/bin/agent",
    "CURSOR_WORKERS_MANIFEST=/etc/cursor-workers/workers.json",
    "CURSOR_WORKERS_LABELS_FILE=/etc/cursor-workers/labels.json",
    "CURSOR_WORKERS_BASE_DIR=${local.base_dir}",
    "CURSOR_WORKERS_GIT_CLEAN_LOCK=/tmp/cursor-worker-git-cleanup.lock",
    "CURSOR_WORKERS_RECONCILE_LOCK=/var/lock/cursor-workers-reconcile.lock",
    "CURSOR_WORKERS_AUTOSCALE_LOCK=/var/lock/cursor-workers-autoscale.lock",
    "CURSOR_WORKERS_DRAIN_MARKER=/run/cursor-workers/draining",
    "CURSOR_ASG_NAME=${var.name_prefix}-workers",
    var.repo_env_mappings == "" ? "" : "CURSOR_REPO_ENV_FILES=/etc/cursor-workers/repo-env-files",
    "CURSOR_WORKER_CLEAN_MODE=full",
    "CURSOR_AUTOSCALE_MIN_IDLE=${var.autoscale_min_idle}",
    "CURSOR_AUTOSCALE_SCALE_STEP=${var.autoscale_scale_step}",
    "CURSOR_AUTOSCALE_MAX_LOCAL_WORKERS=${var.max_local_workers}",
    "CURSOR_AUTOSCALE_BASE_WORKERS=${var.worker_slots_per_instance}",
    "CURSOR_AUTOSCALE_SCALE_DOWN_STEP=${var.autoscale_scale_down_step}",
    "CURSOR_AUTOSCALE_SCALE_DOWN_IDLE_SECONDS=${var.autoscale_scale_down_idle_seconds}",
    "CURSOR_AUTOSCALE_STATE_FILE=/var/lib/cursor-workers/autoscale-state.json",
    "CURSOR_METRICS_NAMESPACE=${var.metric_namespace}",
    ""
  ]))

  user_data = templatefile("${path.module}/../../templates/ec2-user-data.sh.tftpl", {
    worker_user                        = var.worker_user
    cursor_install_url                 = var.cursor_install_url
    git_credential_helper_b64          = base64encode(file("${path.module}/../../../ec2/bin/git-credential-scm-secretsmanager"))
    cursor_worker_start_b64            = base64encode(file("${path.module}/../../../ec2/bin/cursor-worker-start"))
    cursor_workers_reconcile_b64       = base64encode(file("${path.module}/../../../ec2/bin/cursor-workers-reconcile"))
    cursor_workers_autoscale_b64       = base64encode(file("${path.module}/../../../ec2/bin/cursor-workers-autoscale"))
    cursor_workers_drain_b64           = base64encode(file("${path.module}/../../../ec2/bin/cursor-workers-drain"))
    cursor_workers_publish_metrics_b64 = base64encode(file("${path.module}/../../../ec2/bin/cursor-workers-publish-metrics"))
    autoscale_service_b64              = base64encode(file("${path.module}/../../../ec2/systemd/cursor-workers-autoscale.service"))
    autoscale_timer_b64                = base64encode(file("${path.module}/../../../ec2/systemd/cursor-workers-autoscale.timer"))
    metrics_service_b64                = base64encode(file("${path.module}/../../../ec2/systemd/cursor-workers-metrics.service"))
    metrics_timer_b64                  = base64encode(file("${path.module}/../../../ec2/systemd/cursor-workers-metrics.timer"))
    env_file_b64                       = base64encode(local.env_file)
    labels_json_b64                    = base64encode(var.labels_json)
    workers_json_b64                   = base64encode(local.workers_json)
    repo_env_files_b64                 = var.repo_env_mappings == "" ? "" : base64encode(var.repo_env_mappings)
  })

  secret_arns = concat(
    [var.cursor_api_secret_arn, var.scm_token_secret_arn],
    var.repo_env_secret_arns
  )

  asg_tags = merge(var.tags, {
    Name = "${var.name_prefix}-worker"
  })
}

check "compressed_user_data_fits_ec2_limit" {
  assert {
    # Launch Template user data is base64-encoded after gzip compression.
    # 21,848 base64 characters is the ceiling for a 16 KiB decoded payload.
    condition     = length(base64gzip(local.user_data)) <= 21848
    error_message = "Compressed EC2 user data exceeds the 16 KiB Launch Template limit. Move additional bootstrap assets into the AMI or an authenticated artifact store."
  }
}

resource "aws_iam_role" "worker" {
  name               = "${var.name_prefix}-ec2-worker"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "worker" {
  name = "${var.name_prefix}-ec2-worker"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "ReadWorkerSecrets"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = local.secret_arns
        },
        {
          Sid      = "PublishWorkerMetrics"
          Effect   = "Allow"
          Action   = ["cloudwatch:PutMetricData"]
          Resource = "*"
          Condition = {
            StringEquals = {
              "cloudwatch:namespace" = var.metric_namespace
            }
          }
        },
        {
          Sid      = "ReleaseScaleInProtectionAfterDrain"
          Effect   = "Allow"
          Action   = ["autoscaling:SetInstanceProtection"]
          Resource = "arn:aws:autoscaling:${var.aws_region}:${data.aws_caller_identity.current.account_id}:autoScalingGroup:*:autoScalingGroupName/${var.name_prefix}-workers"
        }
      ],
      var.secrets_kms_key_arn == null ? [] : [
        {
          Sid      = "DecryptWorkerSecrets"
          Effect   = "Allow"
          Action   = ["kms:Decrypt"]
          Resource = var.secrets_kms_key_arn
        }
      ]
    )
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.name_prefix}-ec2-worker"
  role = aws_iam_role.worker.name
  tags = var.tags
}

resource "aws_security_group" "worker" {
  name        = "${var.name_prefix}-ec2-worker"
  description = "Cursor worker EC2 instances. No inbound rules; outbound HTTPS and DNS only."
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_egress_rule" "https" {
  for_each          = toset(var.https_egress_cidr_blocks)
  security_group_id = aws_security_group.worker.id
  description       = "Allow outbound HTTPS."
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  for_each          = toset(var.dns_egress_cidr_blocks)
  security_group_id = aws_security_group.worker.id
  description       = "Allow outbound DNS over UDP."
  cidr_ipv4         = each.value
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
}

resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  for_each          = toset(var.dns_egress_cidr_blocks)
  security_group_id = aws_security_group.worker.id
  description       = "Allow outbound DNS over TCP."
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
}

resource "aws_launch_template" "worker" {
  name_prefix   = "${var.name_prefix}-worker-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  # cloud-init automatically detects and decompresses gzip user data.
  user_data              = base64gzip(local.user_data)
  update_default_version = true

  iam_instance_profile {
    name = aws_iam_instance_profile.worker.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  network_interfaces {
    associate_public_ip_address = var.associate_public_ip_address
    security_groups             = [aws_security_group.worker.id]
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      encrypted             = true
      kms_key_id            = var.root_volume_kms_key_id
      volume_size           = var.root_volume_size_gb
      volume_type           = var.root_volume_type
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.asg_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.asg_tags
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

resource "aws_autoscaling_group" "worker" {
  name                  = "${var.name_prefix}-workers"
  min_size              = var.asg_min_size
  desired_capacity      = var.asg_desired_capacity
  max_size              = var.asg_max_size
  vpc_zone_identifier   = var.subnet_ids
  health_check_type     = "EC2"
  protect_from_scale_in = true
  capacity_rebalance    = true

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Default"
  }

  dynamic "tag" {
    for_each = local.asg_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

output "autoscaling_group_name" {
  description = "EC2 worker Auto Scaling Group name."
  value       = aws_autoscaling_group.worker.name
}

output "launch_template_id" {
  description = "EC2 worker Launch Template ID."
  value       = aws_launch_template.worker.id
}

output "security_group_id" {
  description = "EC2 worker security group ID."
  value       = aws_security_group.worker.id
}

output "instance_profile_name" {
  description = "EC2 worker instance profile name."
  value       = aws_iam_instance_profile.worker.name
}

output "compressed_user_data_base64_length" {
  description = "Length of the base64-encoded gzip user-data payload; must remain at or below 21,848 characters."
  value       = length(base64gzip(local.user_data))
}

output "repo_metric_dimension" {
  description = "Repo path used as the CloudWatch Repo dimension (host path without .git)."
  value       = local.repo_path
}
