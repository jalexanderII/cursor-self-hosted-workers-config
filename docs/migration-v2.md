# Migration to the hardened reference

The hardened configuration intentionally changes unsafe defaults.

## SCM variable names

Replace:

- `GITHUB_PAT` with `SCM_TOKEN`
- `GITHUB_PAT_SECRET_ID` with `SCM_TOKEN_SECRET_ID`
- `GITHUB_HOST` with `SCM_HOST`
- Terraform `github_pat_secret_*` with `scm_token_secret_*`
- Kubernetes secret key `pat` with `token`
- `repo_slug` with `repo_url` on the EKS path

The Kubernetes entrypoint temporarily accepts `GITHUB_PAT`, `GITHUB_HOST`, and
`REPO_SLUG` for migration, but new manifests use a read-only token file.

Existing Terraform-managed GitHub PAT secret containers must be imported or
moved to the new `aws_secretsmanager_secret.scm_token` address before apply.
Review the plan carefully to avoid replacing a populated secret.

## Image tags

Replace `latest` and mutable ECR tags with a unique release/commit tag. Existing
mutable repositories can be retained temporarily, but production examples now
expect `IMMUTABLE`.

## EKS

- The greenfield default moves from 1.30 to 1.35.
- The API endpoint is private-only by default.
- Cluster-creator admin is disabled.
- An explicit administrator role ARN is required.

Create and verify the access entry and private network path before disabling
existing public or creator access. Upgrade existing clusters one minor version
at a time; do not jump directly from 1.30 to 1.35.

The worker namespace now enforces restricted Pod Security and uses a dedicated
ServiceAccount, ResourceQuota, and NetworkPolicy. Audit workload destinations,
storage size, node selector, and tolerations before rollout.

## EC2

- Explicit VPC and at least two private subnets are required.
- Production requires a pinned AMI ID.
- Worker density defaults from five to one per host.
- Cleanup changes from `git clean -fd` to `git clean -fdx`.
- Instances are protected from scale-in.
- Automatic instance refresh is removed.

Drain each instance before reducing capacity or starting a refresh. If ignored
caches must persist, opt back into `CURSOR_WORKER_CLEAN_MODE=normal` only for
mutually trusted workloads after reviewing cross-session leakage risk.
