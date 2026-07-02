# Disaster recovery

Workers are replaceable capacity, not durable session storage. Cursor does not
snapshot or restore customer-managed worker disks.

## What to keep durable

- Terraform source and remote state (encrypted, locked)
- Reviewed worker images (by digest)
- Controller chart/image versions and values
- Kubernetes manifests and policies you own
- IAM, network, and secret *references* (values in your secret manager)
- Git history and any build artifacts that must survive
- Centralized logs and audit records

Do not treat `emptyDir`, EC2 root volumes, or local worktrees as backups.
Workspace RPO is the last pushed commit (or other external checkpoint).

## Failure behavior

Controller upgrades and controlled scale-down keep busy workers. Connection
drops may reconnect. Neither restores a lost filesystem after pod, node, or
host failure. For long-running work, agents should commit and push checkpoints.

## EKS rebuild

1. Restore access to Terraform state (or recreate from source).
2. Recreate or select the recovery cluster.
3. Install the pinned controller / CRD.
4. Restore Cursor API key and SCM secrets.
5. Ensure the reviewed worker image is available.
6. Apply platform policy and `WorkerDeployment`.
7. Confirm registration, egress, and a test job before reopening the pool.

Run the control plane across AZs; keep the controller at two replicas with a
PDB. This repo does not implement multi-region failover.

## EC2 rebuild

The ASG recreates instances from the pinned AMI and launch template. Secrets
come from Secrets Manager; repos come from SCM.

Before planned replacement, drain each host over SSM:

```bash
aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo /usr/local/bin/cursor-workers-drain"]'
```

Only scale in or start an instance refresh after drain succeeds. Failed drain
leaves scale-in protection enabled.

## Validate

In a disposable environment, periodically: rebuild the path you run, rotate
credentials, terminate a worker mid-session and confirm expected behavior, drain
and refresh EC2 capacity, and confirm tags, logs, and metrics after recovery.
