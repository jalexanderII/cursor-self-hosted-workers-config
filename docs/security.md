# Security model

Cursor self-hosted workers run inside your AWS account and connect outbound to
Cursor over HTTPS. Cursor still handles orchestration and model inference. The
worker environment is where repo clone, tool execution, tests, builds, and
private network access happen.

## Secrets

Do not commit service account keys, GitHub tokens, kubeconfigs, or repo `.env`
files.

Terraform creates AWS Secrets Manager secret containers but does not set secret
values. Populate values through AWS CLI or your normal secret-management
workflow:

```bash
CURSOR_API_KEY=... make put-secret-cursor-api-key
GITHUB_PAT=... make put-secret-github-pat
```

For Kubernetes, copy secret values into Kubernetes Secrets only after Terraform
has installed the namespace and controller:

```bash
CURSOR_API_KEY=... make kube-create-api-key-secret
GITHUB_PAT=... make kube-create-github-secret
```

Repo env/config files should be stored as raw file bodies. Do not convert large
`.env` files into JSON unless your own tooling requires that.

## IAM

EC2 workers receive an instance profile that can:

- read the configured Cursor API key secret
- read the configured GitHub PAT secret
- read optional repo env/config secrets
- publish CloudWatch metrics to `Cursor/SelfHostedWorkers`
- use SSM Session Manager

The EC2 role does not need write access to Secrets Manager.

EKS worker pods read Kubernetes Secrets. The controller exchanges the long-lived
Cursor service account API key for short-lived worker tokens mounted at
`/var/run/cursor/token`.

## Network

The EC2 security group has no inbound rules. Administration is through SSM.

Workers need outbound HTTPS to:

- Cursor APIs and artifact hosts
- GitHub or your git host
- package registries used by your repo
- AWS APIs for Secrets Manager, ECR, SSM, and CloudWatch
- private services your tests or build steps call

The Terraform defaults allow outbound HTTPS and DNS to `0.0.0.0/0`. Tighten
`egress_cidr_blocks` or attach your own egress controls when you have a known
network policy.

## Isolation

Pool names and Cursor labels are routing metadata, not security boundaries. Use
separate Cursor teams, service accounts, GitHub integrations, AWS accounts,
VPCs, clusters, or worker fleets when tenants need hard isolation.

## Kubernetes hardening

The worker image runs as a non-root user. Production clusters should also apply
your standard controls:

- restricted namespaces and RBAC
- Pod Security Admission or equivalent policy
- network policies or egress controls where supported
- image scanning and pinned image tags
- node group separation if workers should not colocate with other workloads

## Rotation

Rotate the Cursor service account API key and GitHub PAT from their source
systems, then update AWS Secrets Manager and Kubernetes Secrets.

EC2 workers read secrets when worker processes start. Restart idle worker
services or roll the ASG to pick up new values.

Kubernetes workers use controller-managed Cursor tokens, but the controller
still needs the updated API key secret. Update the secret and restart worker pods
if they do not rotate automatically.
