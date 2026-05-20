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
GITHUB_PAT=... make put-secret-github-pat
```

Kubernetes:

```bash
CURSOR_API_KEY=... make kube-create-api-key-secret
GITHUB_PAT=... make kube-create-github-secret
```

EC2 workers read secrets at process start. Restart idle systemd units or roll
instances. EKS workers may need pod restarts after Kubernetes secret updates.

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

## Rollback

EC2:

1. Revert the Terraform/script change.
2. Apply Terraform.
3. Start an ASG instance refresh or terminate bad instances and let the ASG
   replace them.

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
Check `cursor-worker-start` logs. Common causes are bad GitHub credentials,
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
