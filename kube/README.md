# Cursor Self-Hosted Workers on EKS/Kubernetes

This template deploys Cursor self-hosted pool workers on Kubernetes using Cursor's official `worker-set-controller`.

Official docs: https://cursor.com/docs/cloud-agent/self-hosted-k8s

For repeatable production deployment, prefer the Terraform-backed runbooks:

- [`../docs/aws-eks-new-cluster.md`](../docs/aws-eks-new-cluster.md) when this
  repo should create a baseline EKS cluster.
- [`../docs/aws-eks-existing-cluster.md`](../docs/aws-eks-existing-cluster.md)
  when you already have an EKS cluster.

The manual steps below remain useful for debugging and for understanding the
worker image and `WorkerDeployment` shape that Terraform renders.

## Overview

- Installs Cursor's Kubernetes controller with Helm.
- Builds a worker image with `agent`, `git`, and optional Node/pnpm tooling.
- Creates one isolated worker pod per idle worker.
- Clones the repo fresh inside each pod.
- Mounts Kubernetes Secrets for GitHub auth and repo-local env/config files.
- Uses pod names for worker display names and worker directories, so the Cursor UI does not show every worker as `repo`.

## How It Works

EC2 systemd workers share one machine, so they need git worktrees:

```text
/opt/cursor-workers/base
/opt/cursor-workers/worker-2
/opt/cursor-workers/worker-3
```

Kubernetes workers do not need worktrees. Every pod has its own filesystem:

```text
pod repo-workers-abcde -> /workspace/repo-workers-abcde
pod repo-workers-fghij -> /workspace/repo-workers-fghij
```

Each pod starts from a clean clone. When the worker is claimed, `/readyz` becomes not-ready; the controller creates a replacement pod to maintain the configured idle floor.

## Design Notes

- Follow Cursor's Kubernetes docs: use `worker-set-controller`, `WorkerDeployment`, and `--auth-token-file /var/run/cursor/token`.
- Do not store large `.env` files as JSON. Store raw file contents in AWS Secrets Manager, then create Kubernetes Secrets from those raw files.
- Do not bake secrets into the image.
- Apply pod-template changes with the full manifest. Avoid partial patches that replace `spec.template.spec.containers` with only `{name, image}` because that can drop env vars, mounts, probes, and resources.
- `readyReplicas` is the idle ready floor, not a hard max. Total pods can exceed it while agents are busy.
- Pod scaling and node scaling are separate. If pods are `Pending` with `Insufficient cpu`, lower `readyReplicas`, add nodes, or install Cluster Autoscaler/Karpenter.
- Kubernetes pod labels are not Cursor worker labels. Cursor labels must be passed as `--label` flags or equivalent worker config.

## Layout

```text
worker-image/
  Dockerfile
  start-worker.sh

manifests/
  workers.example.yaml
```

## Prerequisites

- Cursor Enterprise with Self-Hosted Cloud Agents enabled.
- Cursor service account API key.
- EKS cluster v1.24+.
- `kubectl` configured for the cluster.
- Helm v3.
- ECR repository for the worker image.
- Outbound HTTPS from worker pods to:
  - `api2.cursor.sh`
  - `api2direct.cursor.sh`
  - `downloads.cursor.com`
  - `cloud-agent-artifacts.s3.us-east-1.amazonaws.com`
  - your git host and package registries

## Optional: Create An EKS Cluster With `eksctl`

Skip this if you already have an EKS cluster.

```bash
eksctl create cluster \
  --name CLUSTER_NAME \
  --region REGION \
  --managed \
  --nodegroup-name cursor-workers-ng \
  --node-type m6i.xlarge \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 10 \
  --with-oidc

aws eks update-kubeconfig --region REGION --name CLUSTER_NAME
kubectl get nodes
```

The node group max is not automatic pod-to-node autoscaling by itself. For cost-aware node scaling, add Cluster Autoscaler or Karpenter. Until then, if workers are `Pending` with `Insufficient cpu`, either lower `readyReplicas` or manually scale the node group.

## 1. Install The Cursor Controller

This is the official Cursor Helm install, using namespace-scoped controller RBAC:

```bash
helm upgrade --install worker-set-controller \
  oci://public.ecr.aws/j6w0t2f5/cursor/worker-set-controller-chart \
  --namespace cursord --create-namespace \
  --version 0.1.0-6c804a0 \
  --set imageTag=6c804a0 \
  --set env.enableAuthManagement=true \
  --set rbac.singleNamespace=true
```

Verify:

```bash
kubectl -n cursord rollout status deployment/worker-set-controller
kubectl get pods -n cursord
```

## 2. Create Kubernetes Secrets

### Cursor Service Account Key

The secret label must match the `WorkerDeployment.metadata.name`.

```bash
CURSOR_API_KEY="$(aws secretsmanager get-secret-value \
  --region REGION \
  --secret-id cursor/self-hosted-workers/cursor-api-key \
  --query SecretString \
  --output text)"

kubectl create secret generic REPLACE_ME-workers-api-key \
  --from-literal=api-key="$CURSOR_API_KEY" \
  -n cursord \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret REPLACE_ME-workers-api-key \
  -n cursord \
  workers.cursor.com/worker-deployment=REPLACE_ME-workers \
  --overwrite

unset CURSOR_API_KEY
```

### GitHub PAT

```bash
GITHUB_PAT="$(aws secretsmanager get-secret-value \
  --region REGION \
  --secret-id cursor/self-hosted-workers/github-pat \
  --query SecretString \
  --output text)"

kubectl create secret generic REPLACE_ME-github \
  --from-literal=pat="$GITHUB_PAT" \
  -n cursord \
  --dry-run=client -o yaml | kubectl apply -f -

unset GITHUB_PAT
```

### Repo Env / Config Files

Use one AWS Secrets Manager secret per file, with the secret string equal to the raw file body. Then copy those secret strings into a Kubernetes Secret as files.

```bash
tmpdir="$(mktemp -d)"

aws secretsmanager get-secret-value \
  --region REGION \
  --secret-id cursor/self-hosted-workers/repos/REPLACE_ME/app.env \
  --query SecretString \
  --output text > "$tmpdir/app.env"

kubectl create secret generic REPLACE_ME-repo-env \
  --from-file=app.env="$tmpdir/app.env" \
  -n cursord \
  --dry-run=client -o yaml | kubectl apply -f -

rm -rf "$tmpdir"
```

In `workers.yaml`, map secret file keys into repo paths:

```yaml
- name: REPO_ENV_MAPPINGS
  value: "app.env:.env"
```

For multiple files:

```yaml
- name: REPO_ENV_MAPPINGS
  value: "api.env:services/api/.env,web.env:apps/web/.env.local"
```

## 3. Build And Push The Worker Image

```bash
cd kube/worker-image

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
AWS_REGION="REGION"
IMAGE_REPO="cursor-worker"
IMAGE_TAG="manual-001"
IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_REPO}:${IMAGE_TAG}"

aws ecr create-repository \
  --region "$AWS_REGION" \
  --repository-name "$IMAGE_REPO" || true

aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker build -t "$IMAGE_URI" .
docker push "$IMAGE_URI"

echo "$IMAGE_URI"
```

Use the printed image URI in `manifests/workers.example.yaml`.

## 4. Apply The WorkerDeployment

Copy and edit the example:

```bash
cp kube/manifests/workers.example.yaml workers.yaml
```

Replace:

- `REPLACE_ME-workers`
- `REPLACE_ME-workers-api-key`
- `REPLACE_ME-github`
- `REPLACE_ME-repo-env`
- `REPLACE_ME-worker`
- `REPLACE_ME-pool`
- `OWNER/REPO`
- `ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/REPLACE_ME-worker:TAG`

Then apply the full manifest:

```bash
kubectl apply -f workers.yaml
```

Verify:

```bash
kubectl get wd -n cursord
kubectl get pods -n cursord -o wide
kubectl logs -n cursord -l app=REPLACE_ME-worker --tail=100
```

Healthy example:

```text
READY   DESIRED   TOTAL   AVAILABLE
3       3         3       True
```

## Scaling

Set idle ready workers:

```bash
kubectl patch wd REPLACE_ME-workers -n cursord --type merge \
  -p '{"spec":{"readyReplicas":5}}'
```

Interpretation:

```text
READY 5 / DESIRED 5 / TOTAL 6
```

means 5 idle workers are ready and 1 extra pod is busy or draining. That is normal.

If pods are `Pending` with `Insufficient cpu`, stabilize first:

```bash
kubectl patch wd REPLACE_ME-workers -n cursord --type merge \
  -p '{"spec":{"readyReplicas":3}}'
```

Then add nodes or lower resource requests if appropriate.

Manual node-group scale example:

```bash
eksctl scale nodegroup \
  --cluster CLUSTER_NAME \
  --region REGION \
  --name cursor-workers-ng \
  --nodes 5 \
  --nodes-min 1 \
  --nodes-max 10
```

## Rollouts

Preferred rollout:

```bash
kubectl apply -f workers.yaml
kubectl get pods -n cursord -w
```

Watch for 60-90 seconds. Stop with `Ctrl+C` if pods rapidly enter `Error`.

Avoid this patch shape:

```bash
# Do not do this: it can replace the full container spec.
kubectl patch wd REPLACE_ME-workers -n cursord --type merge \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"worker","image":"new-image"}]}}}}'
```

If a rollout starts failing, restore a previously working manifest:

```bash
kubectl patch wd REPLACE_ME-workers -n cursord --type merge \
  -p '{"spec":{"readyReplicas":0}}'

kubectl apply -f previous-workers.yaml

kubectl get pods -n cursord --no-headers | awk '$3=="Error"{print $1}' | \
  xargs -r kubectl delete pod -n cursord

kubectl patch wd REPLACE_ME-workers -n cursord --type merge \
  -p '{"spec":{"readyReplicas":3}}'
```

## Debug Commands

List worker deployment state:

```bash
kubectl get wd -n cursord
kubectl get pods -n cursord -o wide
```

Describe pending/error pods:

```bash
kubectl describe pod -n cursord POD_NAME | tail -80
```

Read logs:

```bash
kubectl logs -n cursord POD_NAME --tail=100
kubectl logs -n cursord -l app=REPLACE_ME-worker --tail=100
```

Check health from inside a pod:

```bash
POD="$(kubectl get pods -n cursord -l app=REPLACE_ME-worker -o jsonpath='{.items[0].metadata.name}')"

kubectl exec -n cursord "$POD" -- curl -s -i http://127.0.0.1:8080/healthz
kubectl exec -n cursord "$POD" -- curl -s -i http://127.0.0.1:8080/readyz
```

Check toolchain and mounted env files:

```bash
kubectl exec -n cursord "$POD" -- node --version
kubectl exec -n cursord "$POD" -- pnpm --version
kubectl exec -n cursord "$POD" -- ls -la /workspace
```

Check Cursor CLI flags supported by the image:

```bash
kubectl exec -n cursord "$POD" -- agent worker --help
```

Inspect the current pod template:

```bash
kubectl get wd REPLACE_ME-workers -n cursord -o json | jq '.spec.template.spec.containers[0]'
```

Recent events:

```bash
kubectl get events -n cursord --sort-by=.lastTimestamp | tail -40
```

## Troubleshooting

### `ImagePullBackOff`

- Image URI is wrong.
- ECR permissions are missing.
- Image tag was never pushed.

### `Error` immediately after start

Check logs:

```bash
kubectl logs -n cursord POD_NAME
```

Likely causes:

- unsupported agent CLI flag
- missing `GITHUB_PAT`
- missing mounted repo env file
- bad `REPO_ENV_MAPPINGS`

### `Pending` with `Insufficient cpu`

The cluster cannot schedule enough pods for your ready floor plus busy pods.

Options:

- lower `readyReplicas`
- add nodes
- install Cluster Autoscaler or Karpenter
- lower CPU requests only if the workload can tolerate it

### UI Shows Every Workspace As `repo`

Set these env vars in the WorkerDeployment:

```yaml
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: CURSOR_WORKER_NAME
  value: "$(POD_NAME)"
- name: WORKER_DIR
  value: "/workspace/$(POD_NAME)"
```

This makes each worker use a pod-specific clone path and display name.

## Cleanup

Delete workers:

```bash
kubectl delete wd REPLACE_ME-workers -n cursord
```

Delete controller:

```bash
helm uninstall worker-set-controller -n cursord
```

Delete EKS cluster if this was a test:

```bash
eksctl delete cluster --name CLUSTER_NAME --region REGION
```
