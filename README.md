# Cursor Self-Hosted Cloud Agent Pools on AWS

Composable reference templates for running Cursor Self-Hosted Pool workers on
customer-managed EC2 or EKS infrastructure.

This repository is a production-oriented starting point, not a turnkey managed
service, compliance certification, or hard multi-tenant boundary. Review and
adapt every control to your organization's threat model and platform standards.

## Shared responsibility

Cursor runs the agent loop, orchestration, model inference, worker routing,
conversation experience, and uploaded artifact handling. Your organization owns
the worker filesystem, images, compute, credentials, network policy, monitoring,
capacity, backup, recovery, and incident response.

Self-hosted workers use outbound HTTPS. Selected file contents and tool results
cross to Cursor for inference and orchestration. Artifacts are uploaded to
Cursor-managed storage unless that egress is blocked. Pool names, Cursor labels,
Kubernetes namespaces, and Linux users are not hard tenant-isolation boundaries.

Read [`docs/architecture.md`](docs/architecture.md) and
[`docs/security.md`](docs/security.md) before deployment.

## Deployment paths

- **Existing EKS cluster:** preferred when your organization already operates a
  hardened Kubernetes platform. Start with
  [`docs/aws-eks-existing-cluster.md`](docs/aws-eks-existing-cluster.md).
- **New EKS cluster:** creates a private, multi-AZ baseline with explicit
  administrator access. Start with
  [`docs/aws-eks-new-cluster.md`](docs/aws-eks-new-cluster.md).
- **EC2 Auto Scaling Group:** smaller operational surface using systemd workers.
  The secure default is one worker per host. Start with
  [`docs/aws-ec2-asg.md`](docs/aws-ec2-asg.md).

Cursor also publishes an
[official self-hosted cookbook](https://github.com/cursor/cookbook/tree/main/self-hosted-cloud-agent)
with EC2 container, ECS/Fargate, and EKS examples. This repository adds a
systemd EC2 model, Terraform composition, shared-cluster hardening, FinOps, and
DR guidance. It does not implement ECS/Fargate.

## Prerequisites

- Cursor Enterprise with Self-Hosted Agents enabled
- A Cursor service account API key for pool authentication
- A reviewed HTTPS SCM credential scoped to required repositories
- AWS credentials for the resources you choose to create
- Terraform 1.15.7, AWS CLI, and the platform-specific tools in each runbook
- Private network access to the EKS API when using the production private-only
  cluster profile

Use `mise install` and `mise lint` for the repository's validation toolchain.

## Secret handling

Do not put secret values in `.env`, Terraform variables, command arguments, or
git. Supply `CURSOR_API_KEY` and `SCM_TOKEN` only to the specific Make target
that writes them. Terraform creates secret containers and references, but never
secret values.

External Secrets Operator and Vault remain optional platform integrations. The
repository provides an example without installing those systems.

## EKS quick start

Create or select the cluster and ECR repository first:

```bash
cp .env.example .env
make eks-cluster-init
make eks-cluster-plan
make eks-cluster-apply
```

Configure kubeconfig using the Terraform output, then create worker
infrastructure and build the image:

```bash
eval "$(terraform -chdir=terraform/examples/eks-new-cluster output -raw update_kubeconfig_command)"
make eks-workers-init
make eks-workers-plan
make eks-workers-apply
make ecr-build-push
```

Create secrets from values supplied in the invoking shell, then apply workers:

```bash
CURSOR_API_KEY=... make kube-create-api-key-secret
SCM_TOKEN=... make kube-create-scm-secret
make kube-apply-rendered
make kube-status
```

For an existing EKS cluster, skip the cluster targets.

## EC2 quick start

Production requires explicit VPC/private subnets and a reviewed AMI ID:

```bash
cp terraform/examples/ec2-asg/terraform.tfvars.example \
  terraform/examples/ec2-asg/terraform.tfvars
make ec2-init
make ec2-plan
make ec2-apply
CURSOR_API_KEY=... make put-secret-cursor-api-key
SCM_TOKEN=... make put-secret-scm-token
```

New hosts are protected from ASG scale-in. Run
`/usr/local/bin/cursor-workers-drain` through SSM before reducing capacity or
starting an instance refresh.

## Reference guarantees and non-guarantees

The templates provide:

- EKS namespace-scoped controller RBAC, short-lived worker tokens, restricted
  pod settings, ephemeral workspaces, quotas, and baseline network policy
- EC2 IMDSv2, no inbound security-group rules, SSM administration, encrypted
  disks, local readiness scaling, and explicit drain behavior
- Immutable ECR defaults, scan-on-push, cost tags, and secret values kept out of
  Terraform state
- Credential-free CI validation for Terraform, shell, image, and repository
  contracts

They do not provide:

- automatic multi-region failover or restoration of worker disks
- hard isolation between hostile tenants sharing a cluster or EC2 host
- portable FQDN enforcement through Kubernetes NetworkPolicy
- a managed Karpenter, Cluster Autoscaler, service mesh, observability, Vault,
  or External Secrets installation

## Documentation

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/security.md`](docs/security.md)
- [`docs/networking.md`](docs/networking.md)
- [`docs/finops.md`](docs/finops.md)
- [`docs/disaster-recovery.md`](docs/disaster-recovery.md)
- [`docs/version-maintenance.md`](docs/version-maintenance.md)
- [`docs/migration-v2.md`](docs/migration-v2.md)
- [`docs/operations.md`](docs/operations.md)
- [`docs/production-checklist.md`](docs/production-checklist.md)

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for local validation and change
requirements. No license is granted by this repository unless a license file is
added by its owner.
