# EC2 Auto Scaling Group deployment

This path deploys Cursor self-hosted workers on EC2 with Terraform. Each EC2
instance runs the existing systemd worker fleet from [`../ec2`](../ec2):

- one base checkout plus git worktrees for additional worker slots
- local `/readyz` autoscaling per instance
- CloudWatch metrics from `cursor-workers-publish-metrics`
- SSM access, no inbound security group rules, encrypted root volume, and IMDSv2

Use this path when you want the smallest AWS operational surface and can run a
bounded number of concurrent workers per instance. Use EKS when you want pod
scheduling, Kubernetes-native rollouts, or existing cluster observability.

## Prerequisites

- Cursor Enterprise with Self-Hosted Cloud Agents enabled.
- A Cursor service account API key for pool workers.
- An HTTPS SCM token with least-privilege access to the target repo.
- AWS credentials with EC2, IAM, Auto Scaling, CloudWatch, SSM, and Secrets
  Manager permissions.
- Private subnets with NAT egress, or public subnets if that is your accepted
  network model.

Workers need the exact Cursor and workload destinations listed in
[`networking.md`](networking.md).

## Configure

```bash
cp .env.example .env
```

Edit at least:

```bash
AWS_PROFILE=default
AWS_REGION=us-east-1
DEPLOYMENT_NAME=cursor-workers
REPO_SLUG=YOUR_ORG/YOUR_REPO
REPO_BRANCH=main
CURSOR_WORKER_POOL_NAME=prod-ec2
EC2_INSTANCE_TYPE=m6i.xlarge
TF_VAR_ec2_ami_id=ami-REVIEWED_UBUNTU_2404
EC2_ASG_DESIRED_CAPACITY=2
EC2_WORKER_SLOTS_PER_INSTANCE=1
```

Production requires a reviewed AMI ID, explicit VPC, and at least two private
subnets. Copy
[`../terraform/examples/ec2-asg/terraform.tfvars.example`](../terraform/examples/ec2-asg/terraform.tfvars.example)
to `terraform/examples/ec2-asg/terraform.tfvars` and edit it.

## Deploy

Initialize and review the plan:

```bash
make ec2-init
make ec2-plan
```

Apply when the plan looks right:

```bash
make ec2-apply
```

Terraform creates the secret containers but not the secret values. Populate them
after the first apply:

```bash
CURSOR_API_KEY=... make put-secret-cursor-api-key
SCM_TOKEN=... make put-secret-scm-token
```

To use enterprise-managed secret containers, set
`manage_aws_secret_containers = false` and provide the existing Cursor, SCM, and
repo-environment secret ARNs. The EC2 role remains scoped to only those ARNs.

New instances launched after the secret values exist will bootstrap cleanly. If
instances launched before secrets were populated, terminate them from the ASG or
start an instance refresh.

## Validate

Use SSM to inspect an instance:

```bash
aws ssm start-session --region "$AWS_REGION" --target INSTANCE_ID
```

Then check:

```bash
sudo systemctl status 'cursor-worker-*.service'
sudo journalctl -u 'cursor-worker-*.service' -n 100 --no-pager
sudo journalctl -u cursor-workers-autoscale.service -n 100 --no-pager
for port in $(jq -r '.workers[].managementPort' /etc/cursor-workers/workers.json); do
  curl -s "http://127.0.0.1:${port}/readyz"; echo
done
```

A healthy worker shows as connected and unclaimed when idle. In Cursor Cloud
Agents, choose Self-Hosted and select the configured pool.

## Scale

There are two scaling layers:

- ASG size controls how many EC2 hosts exist.
- Local autoscaling controls how many worker slots each host runs.

Change host count with Terraform:

```hcl
ec2_asg_desired_capacity = 3
ec2_asg_max_size         = 9
```

Change per-host capacity with:

```hcl
ec2_worker_slots_per_instance = 1
ec2_max_local_workers         = 1
```

Each Cursor worker takes one active job. One worker per host is the secure
default. Multi-slot density mode is only for mutually trusted workloads because
workers share a kernel, instance profile, Linux user, and git object database.

## Roll out script changes

The Launch Template user data embeds the current files under `ec2/bin` and
`ec2/systemd`. After changing those files:

```bash
make ec2-plan
make ec2-apply
```

Terraform does not automatically refresh protected worker hosts. Drain each host
with `/usr/local/bin/cursor-workers-drain`, then start the ASG instance refresh.

## Safe scale-in

Instances are protected from ASG scale-in. Before capacity reduction or
replacement, run the drain command through SSM:

```bash
sudo /usr/local/bin/cursor-workers-drain
```

It waits for workers to become idle, stops them, and removes protection. A
timeout leaves protection enabled.

## Repo env/config files

For repo-local `.env` or config files, create one Secrets Manager secret per
file with the raw file body. Then set `repo_env_secret_names` and
`repo_env_mappings` in Terraform:

```hcl
repo_env_secret_names = [
  "cursor/self-hosted-workers/repos/YOUR_REPO/app.env"
]

repo_env_mappings = <<EOF
.env cursor/self-hosted-workers/repos/YOUR_REPO/app.env
EOF
```

The worker injects those files after `git clean` and before registration.

## Cleanup

Drain all hosts first. Destroying this example removes the ASG, IAM, security
group, dashboard, and secret containers:

```bash
terraform -chdir=terraform/examples/ec2-asg destroy
```

Secrets use a recovery window by default. They are scheduled for deletion rather
than immediately destroyed.
