# Disaster recovery

Self-hosted workers are reproducible execution capacity, not durable session
storage. Cursor does not snapshot or restore customer-managed worker disks.

## Durable sources

Keep these outside worker hosts:

- Terraform source and encrypted remote state with locking
- reviewed worker images and image digests
- controller versions and Helm values
- Kubernetes manifests and policies
- AWS IAM and network configuration
- secret values in the enterprise secret manager
- Git branches, commits, and pull requests
- build artifacts and caches that need retention
- centralized logs and audit records

Do not treat pod `emptyDir`, EC2 root disks, or local worktrees as backups.

## Failure behavior

Planned controller updates and Kubernetes scale-down preserve busy workers.
Transient worker connections may reconnect. Neither behavior guarantees
filesystem recovery after pod, node, host, or cluster loss.

An uncommitted active session can lose local changes. Require agents to commit
and push meaningful checkpoints for long-running work.

## EKS recovery

1. Restore access to remote Terraform state.
2. Recreate the VPC/EKS baseline or select the recovery cluster.
3. Install the pinned WorkerDeployment CRD and namespace-scoped controller.
4. Restore/synchronize the bound Cursor API key and SCM Secret.
5. Push or replicate the reviewed worker image.
6. Apply platform policy and `WorkerDeployment`.
7. Verify controller readiness, worker registration, network paths, and a test
   repository before reopening the pool.

Use multiple availability zones and keep the controller at two replicas with
leader election and a PDB. This repository does not implement automatic
multi-region failover.

## EC2 recovery

The ASG should recreate capacity from the pinned AMI and launch template.
Secrets are read from Secrets Manager and repositories are cloned from SCM.

Before planned replacement:

```bash
aws ssm send-command ... --parameters \
  commands='["sudo /usr/local/bin/cursor-workers-drain"]'
```

Only begin scale-in or instance refresh after drain succeeds. A failed drain
leaves the host protected from scale-in.

## RTO and RPO

Define customer-specific objectives for:

- Terraform state recovery
- image availability
- secret-system availability
- SCM availability
- cluster/ASG recreation
- centralized log retention

Workspace RPO is the last external checkpoint, normally a pushed Git commit.
Workspace RTO is not guaranteed because the exact local disk is disposable.

## Testing

At least quarterly:

- rebuild each deployment path in a disposable environment
- rotate Cursor and SCM credentials
- terminate a worker during an active test and confirm expected failure handling
- drain and refresh EC2 capacity
- restore from remote Terraform state
- verify cost tags, logs, metrics, and alarms in the recovered environment
