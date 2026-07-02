# Cursor Self-Hosted Cloud Agent Pools on AWS

Reference templates for running Cursor Self-Hosted Pool workers on customer-managed
EC2 or EKS. Copy what you need, adapt it to your platform standards, and ignore
the rest.

Cursor runs the agent loop, orchestration, model inference, and worker routing.
Your organization owns the worker filesystem, images, compute, credentials,
network policy, monitoring, capacity, and incident response. Workers use outbound
HTTPS only. Pool names, labels, namespaces, and Linux users are not hard
tenant-isolation boundaries.

## Deployment paths

- **Existing EKS cluster:** [`docs/aws-eks-existing-cluster.md`](docs/aws-eks-existing-cluster.md)
- **New EKS cluster:** [`docs/aws-eks-new-cluster.md`](docs/aws-eks-new-cluster.md)
- **EC2 Auto Scaling Group:** [`docs/aws-ec2-asg.md`](docs/aws-ec2-asg.md)

Also see Cursor's
[self-hosted cookbook](https://github.com/cursor/cookbook/tree/main/self-hosted-cloud-agent)
for additional platform examples.

## Prerequisites

- Cursor Enterprise with Self-Hosted Agents enabled
- A Cursor service account API key for the worker pool
- An HTTPS SCM credential scoped to the repositories you need
- AWS credentials for the resources you create
- Terraform, AWS CLI, and the tools listed in each runbook

## Secret handling

Do not put secret values in `.env`, Terraform variables, command arguments, or
git. Pass `CURSOR_API_KEY` and `SCM_TOKEN` only to the Make targets that write
them. Terraform creates secret containers and references, not secret values.

## EKS quick start

```bash
cp .env.example .env
make eks-cluster-init
make eks-cluster-plan
make eks-cluster-apply
eval "$(terraform -chdir=terraform/examples/eks-new-cluster output -raw update_kubeconfig_command)"
make eks-workers-init
make eks-workers-plan
make eks-workers-apply
make ecr-build-push
CURSOR_API_KEY=... make kube-create-api-key-secret
SCM_TOKEN=... make kube-create-scm-secret
make kube-apply-rendered
make kube-status
```

Skip the cluster targets when you already have an EKS cluster. Worker pods
default to the dedicated node label and toleration used by the new-cluster
node group. On a shared node pool, set `worker_node_selector = {}` and
`worker_tolerations = []` before apply.

## EC2 quick start

Set an explicit VPC, private subnets, and AMI ID in `terraform.tfvars`, then:

```bash
cp terraform/examples/ec2-asg/terraform.tfvars.example \
  terraform/examples/ec2-asg/terraform.tfvars
make ec2-init
make ec2-plan
make ec2-apply
CURSOR_API_KEY=... make put-secret-cursor-api-key
SCM_TOKEN=... make put-secret-scm-token
```

Hosts are protected from ASG scale-in. Drain with
`/usr/local/bin/cursor-workers-drain` through SSM before reducing capacity.

## Docs

- [`docs/architecture.md`](docs/architecture.md): control plane vs worker boundary
- [`docs/security.md`](docs/security.md): isolation and credentials
- [`docs/networking.md`](docs/networking.md): required egress
- [`docs/finops.md`](docs/finops.md): usage vs infrastructure chargeback
- [`docs/disaster-recovery.md`](docs/disaster-recovery.md): ephemeral workers and rebuild
- [`docs/operations.md`](docs/operations.md): rotate, scale, drain, tear down
