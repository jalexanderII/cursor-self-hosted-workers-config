# Operations

## Path choice

| Path | When |
| --- | --- |
| EC2 ASG | Small fleet, simple AWS primitives |
| EKS | Existing Kubernetes platform, pod scheduling, K8s rollouts |

## Secret rotation

```bash
# AWS Secrets Manager (EC2 and shared secret containers)
CURSOR_API_KEY=... make put-secret-cursor-api-key
SCM_TOKEN=... make put-secret-scm-token

# Kubernetes Secrets used by the WorkerDeployment
CURSOR_API_KEY=... make kube-create-api-key-secret
SCM_TOKEN=... make kube-create-scm-secret
```

`CURSOR_API_KEY` must be a Cursor service-account or team key for pool workers.

EC2 workers read secrets at process start. Restart only **idle** units, or
replace hosts after the first secret write with `make ec2-recycle` (scale-in
protection blocks a plain terminate). Kubernetes: the controller refreshes
short-lived worker tokens; the long-lived API key is not mounted into worker
pods.

## Health

**EC2** (from your laptop):

```bash
make ec2-status
```

**EC2** (on the instance):

```bash
sudo systemctl status 'cursor-worker-*.service'
sudo journalctl -u 'cursor-worker-*.service' -f

for port in $(jq -r '.workers[].managementPort' /etc/cursor-workers/workers.json); do
  echo -n "$port "; curl -s -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:${port}/readyz"
done
```

**EKS:**

```bash
kubectl get wd,pods -n "$K8S_NAMESPACE" -o wide
kubectl logs -n "$K8S_NAMESPACE" -l app="$WORKER_DEPLOYMENT_NAME" --tail=100
```

## Scaling

**EC2:** change ASG size in Terraform. Per-host slots (only for trusted
multi-slot setups):

```hcl
ec2_worker_slots_per_instance = 1
ec2_max_local_workers         = 1
```

Local autoscaling uses that host's `/readyz` and `/metrics` only.

**EKS:** `worker_ready_replicas` is the idle floor. Provide node capacity
separately (node group, Cluster Autoscaler, or Karpenter).

Default team limit is 50 workers unless Cursor approves more. Repo-scoped
service account keys must allow the repos you run.

Optional demand signal (authenticated Admin/fleet API): pending pool requests.
Prefer local readiness for EC2 slot decisions so one fleet does not react to
another.

## EC2 drain

Instances are protected from ASG scale-in. Before reducing capacity or starting
a refresh:

```bash
sudo /usr/local/bin/cursor-workers-drain
```

Stops local autoscale, waits for every worker `/readyz` = 200, stops workers,
removes protection. Timeout → non-zero exit, protection stays on.

## Rollback

**EC2:** revert AMI/Terraform → apply → drain old instances → instance refresh
only when drains succeed.

**EKS:** re-apply the last good `WorkerDeployment`. If pods crash-loop, set
`readyReplicas: 0`, restore the manifest, then scale the floor back up.

## Common failures

| Symptom | Check |
| --- | --- |
| `AccessDenied` on secrets | Instance profile / secret name; values must be written separately from Terraform |
| Worker registered but jobs miss the repo | Cursor repo authorization and worker `REPO_URL` / routing |
| Pods `Pending` | CPU/memory, CNI IPs, taints, image pull, node count |
| EC2 workers restarting | `cursor-worker-start` logs: SCM creds, repo access, API key, CLI flags |

## Cleanup

Drain EC2 hosts (or set EKS `readyReplicas: 0` and wait) before destroy:

```bash
kubectl delete -f terraform/examples/eks-existing-cluster/rendered/workers.yaml || true
terraform -chdir=terraform/examples/eks-existing-cluster destroy
terraform -chdir=terraform/examples/eks-new-cluster destroy
terraform -chdir=terraform/examples/ec2-asg destroy
```

Secrets Manager entries may remain until their recovery window expires.

See [`disaster-recovery.md`](disaster-recovery.md).
