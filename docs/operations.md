# Operations runbook

This runbook covers common operations for both EC2 and EKS deployments.

## Choose the right path

- Use EC2 ASG for a compact deployment with a small worker fleet and simple AWS
  primitives.
- Use EKS when you already operate Kubernetes or need pod-level scheduling,
  cluster observability, and Kubernetes rollout controls.

## Secret rotation

AWS Secrets Manager:

```bash
CURSOR_API_KEY=... make put-secret-cursor-api-key
SCM_TOKEN=... make put-secret-scm-token
```

Kubernetes:

```bash
CURSOR_API_KEY=... make kube-create-api-key-secret
SCM_TOKEN=... make kube-create-scm-secret
```

EC2 workers read secrets at process start. Restart only idle systemd units.
Kubernetes controller-managed worker tokens rotate without exposing the
long-lived Cursor key to worker pods.

## EC2 health

On an instance:

```bash
sudo systemctl status 'cursor-worker-*.service'
sudo journalctl -u 'cursor-worker-*.service' -f
sudo journalctl -u cursor-workers-autoscale.service -n 100 --no-pager
sudo journalctl -u cursor-workers-metrics.service -n 100 --no-pager
```

Check local worker readiness:

```bash
for port in $(jq -r '.workers[].managementPort' /etc/cursor-workers/workers.json); do
  echo -n "$port "
  curl -s "http://127.0.0.1:${port}/readyz"
  echo
done
```

CloudWatch dashboard:

```bash
terraform -chdir=terraform/examples/ec2-asg output cloudwatch_dashboard_name
```

## EKS health

```bash
kubectl get wd -n "$K8S_NAMESPACE"
kubectl get pods -n "$K8S_NAMESPACE" -o wide
kubectl logs -n "$K8S_NAMESPACE" -l app="$WORKER_DEPLOYMENT_NAME" --tail=100
kubectl get events -n "$K8S_NAMESPACE" --sort-by=.lastTimestamp
```

Inside a pod:

```bash
POD="$(kubectl get pods -n "$K8S_NAMESPACE" -l app="$WORKER_DEPLOYMENT_NAME" -o jsonpath='{.items[0].metadata.name}')"
kubectl exec -n "$K8S_NAMESPACE" "$POD" -- curl -s -i http://127.0.0.1:8080/healthz
kubectl exec -n "$K8S_NAMESPACE" "$POD" -- curl -s -i http://127.0.0.1:8080/readyz
```

## Scaling

EC2 has host scaling and local worker-slot scaling. Change ASG capacity in
Terraform, and tune per-instance worker slots with:

```hcl
ec2_worker_slots_per_instance = 5
ec2_max_local_workers         = 15
```

EKS has worker replica scaling and node scaling. Change Cursor idle capacity
with:

```hcl
worker_ready_replicas = 5
```

Add node capacity separately through the EKS node group, Cluster Autoscaler, or
Karpenter.

The Cursor fleet API also exposes pending pool requests. Use it as an optional
demand signal for an external scaler. Keep local EC2 scaling based on each
host's documented `/readyz` and `/metrics` endpoints so one fleet does not react
to another fleet's capacity.

```text
GET https://api.cursor.com/v0/private-workers/pending-requests
```

Repo-scoped service account keys must pass the corresponding repository filter.

The default team limit is 50 workers unless Cursor approves a larger fleet.

## EC2 drain and instance refresh

EC2 instances are protected from ASG scale-in. Before reducing desired capacity
or starting a refresh, run:

```bash
sudo /usr/local/bin/cursor-workers-drain
```

The script:

1. stops local autoscaling
2. waits until every worker returns HTTP 200 from `/readyz`
3. stops worker services
4. removes scale-in protection from that instance

If the timeout expires, the script exits non-zero and leaves protection enabled.
Never bypass this for a host that may have an active session.

## Rollback

EC2:

1. Revert the Terraform/script or pinned AMI change.
2. Apply Terraform to create a reviewed Launch Template version.
3. Drain each old instance.
4. Start an ASG instance refresh only after the affected instances are safe.

EKS:

1. Re-apply the last known-good rendered WorkerDeployment manifest.
2. Watch pods for 60 to 90 seconds.
3. If pods crash fast, scale `readyReplicas` to 0, restore the manifest, then
   scale back up.

## Common failures

`AccessDenied` reading secrets:
Check the EC2 instance profile or Kubernetes secret name. Terraform creates AWS
secret containers, but values must be populated separately.

Worker registers but Cloud Agents cannot use the repo:
Confirm the Cursor GitHub App has access to the repo and the worker `REPO_SLUG`
matches the Cloud Agent job repo.

EKS pods are pending:
Check CPU, memory, CNI IP capacity, taints, image pull errors, and node group
size.

EC2 workers keep restarting:
Check `cursor-worker-start` logs. Common causes are bad SCM credentials,
missing repo access, invalid Cursor API key, or an unsupported agent CLI flag.

## Cleanup

Destroy in dependency order:

```bash
kubectl delete -f terraform/examples/eks-existing-cluster/rendered/workers.yaml || true
terraform -chdir=terraform/examples/eks-existing-cluster destroy
terraform -chdir=terraform/examples/eks-new-cluster destroy
terraform -chdir=terraform/examples/ec2-asg destroy
```

AWS Secrets Manager secrets may remain in scheduled deletion until the configured
recovery window expires.

For EC2, drain all hosts before reducing the ASG or destroying the stack. For
EKS, set `readyReplicas: 0` and wait for active sessions to finish before
deleting the WorkerDeployment.

See [`disaster-recovery.md`](disaster-recovery.md) for recovery testing.
