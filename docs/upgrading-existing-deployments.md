# Upgrading an existing deployment

Skip this document if you are adopting these examples for the first time. Use
the current runbooks and defaults only.

If you already applied an earlier commit of this repository, the examples in
this tree intentionally use stricter defaults and different variable names.
Review the Terraform plan carefully before apply. Some changes rename resources
or remove access paths; a blind apply can replace a secret, lock out the API,
or interrupt active sessions.

## SCM credential names

Earlier examples used GitHub-specific names. Current examples are SCM-agnostic:

| Earlier | Current |
| --- | --- |
| `GITHUB_PAT` | `SCM_TOKEN` |
| `GITHUB_PAT_SECRET_ID` | `SCM_TOKEN_SECRET_ID` |
| `GITHUB_HOST` | `SCM_HOST` |
| Terraform `github_pat_secret_*` | `scm_token_secret_*` |
| Kubernetes secret key `pat` | `token` |
| EKS `repo_slug` | `repo_url` |

The Kubernetes worker entrypoint still accepts `GITHUB_PAT`, `GITHUB_HOST`, and
`REPO_SLUG` so existing pods do not fail immediately, but new manifests mount a
read-only token file and set `SCM_*` variables.

If Terraform previously created a GitHub PAT secret, move or import that state
to `aws_secretsmanager_secret.scm_token` before apply so a populated secret is
not destroyed and recreated.

## Image tags

Earlier examples often used `latest` or other mutable ECR tags. Current
examples expect a unique release or commit tag and an immutable repository
policy. Update your image build and `WORKER_IMAGE_TAG` before cutting over.

## EKS defaults that changed

| Earlier | Current |
| --- | --- |
| Kubernetes 1.30 | Kubernetes 1.35 (greenfield example only) |
| Public or open endpoint patterns | Private-only API endpoint by default |
| Cluster-creator admin enabled | Explicit administrator role ARN required |

If you already run a cluster with public endpoint access or creator admin:

1. Create and verify the new access entry and private network path first.
2. Only then disable public or creator access.
3. Upgrade existing clusters one minor version at a time; do not jump from
   1.30 to 1.35 in one step.

Worker namespaces now enforce restricted Pod Security and create a dedicated
ServiceAccount, ResourceQuota, and NetworkPolicy. Confirm workload egress,
ephemeral storage size, node selectors, and tolerations before rollout.

## EC2 defaults that changed

| Earlier | Current |
| --- | --- |
| Implied or incomplete network inputs | Explicit VPC and at least two private subnets |
| Latest AMI lookup | Pinned `ec2_ami_id` for production |
| Five workers per host | One worker per host |
| `git clean -fd` after a session | `git clean -fdx` after a session |
| Easy scale-in | Instances protected from scale-in |
| Automatic instance refresh enabled | Automatic refresh removed |

Drain each instance before reducing capacity or starting a refresh. If ignored
caches must persist across sessions, set `CURSOR_WORKER_CLEAN_MODE=normal` only
for mutually trusted workloads after reviewing cross-session leakage risk.
