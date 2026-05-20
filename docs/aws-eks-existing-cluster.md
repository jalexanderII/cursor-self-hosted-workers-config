# Existing EKS cluster deployment

This path installs Cursor self-hosted workers into an existing Kubernetes/EKS
cluster. Terraform manages:

- ECR for the worker image
- AWS Secrets Manager secret containers
- the `cursord` namespace
- Cursor's official `worker-set-controller` Helm release
- a labels ConfigMap
- a rendered `WorkerDeployment` manifest written to
  `terraform/examples/eks-existing-cluster/rendered/workers.yaml`

Secret values and the `WorkerDeployment` apply are intentionally outside
Terraform state.

## Prerequisites

- A working EKS cluster and kubeconfig.
- Helm 3 and `kubectl`.
- Docker buildx for the worker image.
- Cursor service account API key.
- GitHub PAT for the target repo.

## Configure

```bash
cp .env.example .env
```

Edit at least:

```bash
AWS_REGION=us-east-1
EKS_WORKERS_TF_DIR=terraform/examples/eks-existing-cluster
K8S_NAMESPACE=cursord
WORKER_DEPLOYMENT_NAME=cursor-workers
REPO_SLUG=YOUR_ORG/YOUR_REPO
REPO_BRANCH=main
CURSOR_WORKER_POOL_NAME=prod-eks
WORKER_READY_REPLICAS=3
```

If your kubeconfig current context is not the target cluster, set
`TF_VAR_kube_context` in `.env` or create
`terraform/examples/eks-existing-cluster/terraform.tfvars` from the example.

## Deploy infrastructure

```bash
make eks-workers-init
make eks-workers-plan
make eks-workers-apply
```

This installs the controller and writes the rendered WorkerDeployment YAML. It
does not create Kubernetes secrets with secret values.

## Push the worker image

```bash
make ecr-build-push
```

For a stricter release flow, set a unique `WORKER_IMAGE_TAG` per release and set
`ecr_image_tag_mutability = "IMMUTABLE"` in Terraform.

## Create Kubernetes secrets

```bash
CURSOR_API_KEY=... make kube-create-api-key-secret
GITHUB_PAT=... make kube-create-github-secret
```

For repo env/config files, create a Kubernetes Secret from files:

```bash
kubectl create secret generic cursor-workers-repo-env \
  --from-file=app.env=./app.env \
  -n cursord \
  --dry-run=client -o yaml | kubectl apply -f -
```

Then set these Terraform vars before rendering again:

```hcl
repo_env_secret_name_k8s = "cursor-workers-repo-env"
repo_env_mappings        = "app.env:.env"
```

## Apply workers

Review the rendered manifest:

```bash
less terraform/examples/eks-existing-cluster/rendered/workers.yaml
```

Apply:

```bash
make kube-apply-rendered
make kube-status
```

Validate logs:

```bash
kubectl logs -n "$K8S_NAMESPACE" -l app="$WORKER_DEPLOYMENT_NAME" --tail=100
kubectl get wd -n "$K8S_NAMESPACE"
```

## Scale

`readyReplicas` is the idle ready floor, not a hard maximum. If three workers are
busy and `readyReplicas = 3`, the controller can run six pods while preserving
three idle workers.

Change:

```hcl
worker_ready_replicas = 5
```

Then:

```bash
make eks-workers-apply
make kube-apply-rendered
```

Node capacity is separate. Pending pods usually mean insufficient CPU, memory,
IP addresses, image pull permissions, or node taints.

## Roll out image changes

Build and push a new tag:

```bash
WORKER_IMAGE_TAG=release-2026-05-20 make ecr-build-push
```

Update Terraform with the same tag, apply, then apply the rendered manifest.

Avoid partial patches against `spec.template.spec.containers`; for this CRD they
can replace the full container spec and drop probes, env vars, mounts, or
resources.

## Cleanup

Delete workers before removing the controller:

```bash
kubectl delete -f terraform/examples/eks-existing-cluster/rendered/workers.yaml
terraform -chdir=terraform/examples/eks-existing-cluster destroy
```
