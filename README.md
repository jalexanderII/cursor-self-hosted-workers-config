# Cursor Self-Hosted Cloud Agents Templates

Production-oriented templates for running Cursor self-hosted Cloud Agent workers
on customer-managed AWS infrastructure.

The repo has two layers:

- Runtime assets in [`ec2/`](ec2/) and [`kube/`](kube/) that define how workers
  start, clean workspaces, scale, and report health.
- Terraform examples in [`terraform/examples/`](terraform/examples/) that make
  those runtime assets repeatable for EC2 Auto Scaling Groups and EKS.

Cursor still owns orchestration, model inference, and the Cloud Agents user
experience. These workers connect outbound to Cursor over HTTPS and run inside
your AWS account so they can reach your repos and private services.

## Deployment paths

| Path | Use when | Start here |
| --- | --- | --- |
| EC2 Auto Scaling Group | You want a small AWS footprint with systemd workers, git worktrees, local autoscaling, and CloudWatch metrics. | [`docs/aws-ec2-asg.md`](docs/aws-ec2-asg.md) |
| Existing EKS cluster | You already have a production EKS/VPC baseline and want to add Cursor workers. | [`docs/aws-eks-existing-cluster.md`](docs/aws-eks-existing-cluster.md) |
| New EKS cluster | You want this repo to create a baseline EKS cluster before installing workers. | [`docs/aws-eks-new-cluster.md`](docs/aws-eks-new-cluster.md) |

## Quick start

Copy the local environment template:

```bash
cp .env.example .env
```

Edit `.env` for your AWS account, repo, Cursor worker pool, and secret names.
Secret values such as `CURSOR_API_KEY` and `GITHUB_PAT` belong only in your local
`.env` or shell.

Create the AWS secret containers with Terraform, then populate the secret values
outside Terraform:

```bash
make ec2-init
make ec2-plan
make ec2-apply
make put-secret-cursor-api-key
make put-secret-github-pat
```

For EKS, build and push the worker image before applying the rendered worker
manifest:

```bash
make ecr-build-push
make eks-workers-init
make eks-workers-plan
```

## What is production-ready here

- Terraform modules for ECR, Secrets Manager, EC2 ASGs, EKS clusters, worker
  controller installation, and EC2 CloudWatch dashboards.
- EC2 workers run under systemd with clean git worktrees, conservative local
  autoscaling, and per-instance CloudWatch metrics.
- EKS workers use Cursor's official `worker-set-controller`, short-lived worker
  tokens, fresh pod-local clones, readiness probes, liveness probes, and resource
  requests.
- Secrets are deliberately a two-step flow. Terraform creates names, ARNs, IAM,
  and Kubernetes references; secret values are written with AWS CLI or `kubectl`
  so they do not land in Terraform state.

## Existing manual templates

The original hand-run guides are still useful when debugging or adapting the
runtime behavior directly:

- [`ec2/`](ec2/) - EC2 systemd worker fleet, worktrees, local autoscaling, and
  CloudWatch metrics.
- [`kube/`](kube/) - Kubernetes/EKS worker image and `WorkerDeployment` example.

## Operations and security

Read [`docs/security.md`](docs/security.md) before deploying into a shared AWS
account. Read [`docs/operations.md`](docs/operations.md) for rotation, scaling,
rollouts, rollback, and cleanup.
