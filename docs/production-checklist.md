# Production readiness checklist

## Cursor

- [ ] Enterprise Self-Hosted Agents are enabled.
- [ ] Pool workers use a dedicated service account key.
- [ ] Repository access is authorized at the Cursor team level.
- [ ] Pool and repository routing are tested.
- [ ] Expected capacity is within the approved worker limit.

## Identity and secrets

- [ ] Secret values never enter Terraform state or committed files.
- [ ] Cursor and SCM credentials are scoped per trust domain.
- [ ] Kubernetes uses controller-managed short-lived worker tokens.
- [ ] Workload AWS access uses a dedicated IRSA/Pod Identity role when needed.
- [ ] Rotation and emergency revocation have been tested.

## Network

- [ ] Required Cursor hosts and exact artifact host are allowed.
- [ ] SCM, registry, AWS, and internal-service egress is documented.
- [ ] Destination-level egress controls exist outside portable NetworkPolicy.
- [ ] No worker application ingress is exposed.
- [ ] Long-lived connections work through proxies or service mesh.

## Isolation

- [ ] Shared-cluster workloads belong to one organizational trust boundary.
- [ ] Each security domain has separate namespace, WorkerDeployment, identities,
      secrets, policies, quota, and cost labels.
- [ ] Dedicated nodes/clusters/accounts are used where namespace isolation is
      insufficient.
- [ ] No RWX workspace is shared across trust boundaries.

## EKS

- [ ] Kubernetes version is in EKS standard support.
- [ ] API endpoint is private or public access uses narrow CIDRs.
- [ ] Administrator access uses explicit EKS access entries.
- [ ] Worker pods pass restricted Pod Security.
- [ ] Ephemeral-storage requests, limits, and workspace size are appropriate.
- [ ] Controller has two replicas, leader election, and a PDB.
- [ ] Node capacity can cover busy workers plus `readyReplicas`.
- [ ] Logs persist after terminal pods are reaped.

## EC2

- [ ] VPC, private subnets, and AMI ID are explicit.
- [ ] One worker per host is used unless workloads are mutually trusted.
- [ ] HTTPS egress routes through approved controls.
- [ ] Host scale-in protection is enabled.
- [ ] Drain succeeds before scale-in or instance refresh.
- [ ] Bootstrap, worker, autoscaler, and metrics logs are monitored.

## Supply chain

- [ ] ECR is immutable and workers use a unique tag or digest.
- [ ] ECR scan results are reviewed before promotion.
- [ ] Base image and Cursor installer source are reviewed.
- [ ] CI validation and secret scanning are required before merge.

## Operations and recovery

- [ ] Remote Terraform state is encrypted and locked.
- [ ] Upgrade and rollback have been rehearsed.
- [ ] Worker loss during an active test has been exercised.
- [ ] Images, secrets, SCM, and logs meet the required RTO/RPO.
- [ ] FinOps labels/tags reconcile to Cursor usage and AWS cost data.
