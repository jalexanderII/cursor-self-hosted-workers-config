# Kubernetes / EKS workers

Worker image, manifest examples, and entrypoint for Cursor Self-Hosted pools on
Kubernetes.

Preferred path: [`../docs/aws-eks-existing-cluster.md`](../docs/aws-eks-existing-cluster.md)
(or [`../docs/aws-eks-new-cluster.md`](../docs/aws-eks-new-cluster.md) if you also
need a baseline cluster). Official product docs:
[Self-Hosted on Kubernetes](https://cursor.com/docs/cloud-agent/self-hosted-k8s).

## Layout

```text
worker-image/          Minimal image (agent CLI + git) and start-worker.sh
manifests/             Example WorkerDeployment and optional platform resources
integrations/          Optional External Secrets examples (you install ESO)
```

Terraform renders `manifests/workers.tpl.yaml` into
`terraform/examples/eks-existing-cluster/rendered/workers.yaml`. Use
`manifests/workers.example.yaml` when applying by hand. Use
`manifests/platform.example.yaml` only if you are not letting Terraform create
the namespace, ServiceAccount, quota, and baseline NetworkPolicy.

## Behavior that matters

- Each pod is one worker with a fresh clone on ephemeral storage. No shared
  worktrees.
- Use the pod name for `CURSOR_WORKER_NAME` / `WORKER_DIR` so the Cursor UI does
  not label every worker `repo`.
- The controller exchanges the long-lived API key for a short-lived token at
  `/var/run/cursor/token`. Mount SCM credentials as a file, not in `REPO_URL`.
- `readyReplicas` is an idle floor, not a max. Busy pods are kept; node capacity
  must cover busy workers plus the floor.
- Apply the full WorkerDeployment for image or pod-template changes. Partial
  patches that only set `containers: [{name, image}]` can drop env, mounts, and
  probes on this CRD.
- Kubernetes labels are not Cursor worker labels. Pass Cursor labels via
  `CURSOR_WORKER_LABELS` / `--label`. Do not set reserved `repo` or `pool`
  labels yourself; the pool comes from `--pool-name`.

## Customize the image

The stock image is intentionally minimal. Derive a repo-specific image when the
agent needs language runtimes, build tools, or internal certificates:

```bash
make ecr-build-push
```

Or build `worker-image/` directly and push to your registry.

## Manual apply (without Terraform)

1. Install the controller (version pins live in
   `terraform/modules/eks-workers/main.tf` and the manifest comments).
2. Create the API-key and SCM secrets (`scripts/create-k8s-secret.sh` or your
   platform secret sync).
3. Edit and apply `manifests/platform.example.yaml` if needed, then
   `manifests/workers.example.yaml`.

```bash
CURSOR_API_KEY=... make kube-create-api-key-secret
SCM_TOKEN=... make kube-create-scm-secret
make kube-apply-rendered   # when using the Terraform rendered manifest
```

Egress requirements are in [`../docs/networking.md`](../docs/networking.md).
Operations (rotation, scaling, drain/teardown) are in
[`../docs/operations.md`](../docs/operations.md).
