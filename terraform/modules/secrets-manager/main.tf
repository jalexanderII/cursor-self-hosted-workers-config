variable "cursor_api_secret_name" {
  description = "Secrets Manager secret name for the Cursor service account API key."
  type        = string
}

variable "github_pat_secret_name" {
  description = "Secrets Manager secret name for the GitHub PAT used by workers."
  type        = string
}

variable "repo_env_secret_names" {
  description = "Optional Secrets Manager secret names for repo-local env/config files."
  type        = list(string)
  default     = []
}

variable "recovery_window_in_days" {
  description = "Secrets Manager recovery window. Use 7 or more for production."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to secret containers."
  type        = map(string)
  default     = {}
}

resource "aws_secretsmanager_secret" "cursor_api_key" {
  name                    = var.cursor_api_secret_name
  description             = "Cursor service account API key for self-hosted Cloud Agent workers."
  recovery_window_in_days = var.recovery_window_in_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret" "github_pat" {
  name                    = var.github_pat_secret_name
  description             = "GitHub PAT used by self-hosted Cloud Agent workers."
  recovery_window_in_days = var.recovery_window_in_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret" "repo_env" {
  for_each = toset(var.repo_env_secret_names)

  name                    = each.value
  description             = "Repo-local env/config file for self-hosted Cursor workers."
  recovery_window_in_days = var.recovery_window_in_days
  tags                    = var.tags
}

output "cursor_api_secret_name" {
  description = "Cursor API key secret name."
  value       = aws_secretsmanager_secret.cursor_api_key.name
}

output "cursor_api_secret_arn" {
  description = "Cursor API key secret ARN."
  value       = aws_secretsmanager_secret.cursor_api_key.arn
}

output "github_pat_secret_name" {
  description = "GitHub PAT secret name."
  value       = aws_secretsmanager_secret.github_pat.name
}

output "github_pat_secret_arn" {
  description = "GitHub PAT secret ARN."
  value       = aws_secretsmanager_secret.github_pat.arn
}

output "repo_env_secret_arns" {
  description = "Repo-local env/config secret ARNs."
  value       = [for secret in aws_secretsmanager_secret.repo_env : secret.arn]
}
