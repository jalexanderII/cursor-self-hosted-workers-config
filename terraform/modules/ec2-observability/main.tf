variable "dashboard_name" {
  description = "CloudWatch dashboard name."
  type        = string
}

variable "metric_namespace" {
  description = "Namespace used by cursor-workers-publish-metrics."
  type        = string
  default     = "Cursor/SelfHostedWorkers"
}

variable "repo_slug" {
  description = "Repo dimension emitted by the EC2 metrics publisher."
  type        = string
}

variable "alarm_instance_ids" {
  description = "Optional stable instance IDs to alarm on. ASG fleets usually leave this empty and use the dashboard plus external alerting."
  type        = list(string)
  default     = []
}

variable "alarm_actions" {
  description = "SNS topic ARNs or other CloudWatch alarm actions."
  type        = list(string)
  default     = []
}

resource "aws_cloudwatch_dashboard" "workers" {
  dashboard_name = var.dashboard_name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          title   = "Cursor EC2 workers by repo"
          region  = data.aws_region.current.name
          view    = "timeSeries"
          stacked = false
          metrics = [
            [{ expression = "SEARCH('{${var.metric_namespace},InstanceId,Repo} MetricName=\"TotalWorkers\" Repo=\"${var.repo_slug}\"', 'Sum', 60)", label = "TotalWorkers", id = "total" }],
            [{ expression = "SEARCH('{${var.metric_namespace},InstanceId,Repo} MetricName=\"ReadyWorkers\" Repo=\"${var.repo_slug}\"', 'Sum', 60)", label = "ReadyWorkers", id = "ready" }],
            [{ expression = "SEARCH('{${var.metric_namespace},InstanceId,Repo} MetricName=\"ClaimedWorkers\" Repo=\"${var.repo_slug}\"', 'Sum', 60)", label = "ClaimedWorkers", id = "claimed" }],
            [{ expression = "SEARCH('{${var.metric_namespace},InstanceId,Repo} MetricName=\"FailedWorkerServices\" Repo=\"${var.repo_slug}\"', 'Sum', 60)", label = "FailedWorkerServices", id = "failed" }]
          ]
          stat   = "Sum"
          period = 60
        }
      },
      {
        type   = "text"
        width  = 12
        height = 3
        properties = {
          markdown = "EC2 worker metrics are emitted per instance with dimensions `InstanceId` and `Repo`. For ASG fleets, alerting is usually wired in your central observability system by searching this namespace and repo dimension."
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "failed_worker_services" {
  for_each = toset(var.alarm_instance_ids)

  alarm_name          = "${var.dashboard_name}-${each.value}-failed-worker-services"
  alarm_description   = "One or more Cursor worker systemd services are failed on ${each.value}."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FailedWorkerServices"
  namespace           = var.metric_namespace
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "missing"
  alarm_actions       = var.alarm_actions

  dimensions = {
    InstanceId = each.value
    Repo       = var.repo_slug
  }
}

data "aws_region" "current" {}

output "dashboard_name" {
  description = "CloudWatch dashboard name."
  value       = aws_cloudwatch_dashboard.workers.dashboard_name
}
