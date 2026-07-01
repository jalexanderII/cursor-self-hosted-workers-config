# Architecture and responsibility boundaries

## Data and control flow

```text
User or automation
       |
       v
Cursor cloud: agent loop, orchestration, inference, routing, conversation UI
       |
       | outbound worker connection carries tool requests and results
       v
Customer worker: repository, shell, filesystem, local MCP, private services
```

The worker establishes a long-lived outbound HTTPS connection. Cursor does not
open an inbound connection to the worker.

Cursor owns:

- agent planning and inference
- conversation/run orchestration
- selection of eligible workers by repo and pool
- product integrations and uploaded artifacts
- Cursor-side usage telemetry

The customer owns:

- worker images, filesystems, repositories, and cleanup
- Kubernetes/EC2 compute and infrastructure capacity
- SCM and workload credentials
- network policy and access to internal services
- logging, monitoring, incident response, backup, and recovery

## Kubernetes lifecycle

`WorkerDeployment.spec.readyReplicas` is an idle-ready floor, not a maximum.

1. A pod starts and registers as a pool worker.
2. `/readyz` returns HTTP 200 while connected and idle.
3. Cursor assigns a session; `/readyz` becomes non-200.
4. The controller creates another pod to restore the idle floor.
5. The busy pod remains alive during scale-down and rolling updates.
6. After the session and idle timeout, the CLI exits and the pod is replaced.

Use the Cursor controller for worker-pod lifecycle and Cluster Autoscaler,
Karpenter, or EKS Auto Mode for node lifecycle. Do not attach an HPA directly to
the controller-managed worker pods.

## EC2 lifecycle

Each systemd unit owns one workspace and worker process. The secure default is
one unit per host.

The local autoscaler uses documented local interfaces:

- `/readyz` HTTP 200 means connected and idle
- `/metrics` reports connection and active-session state
- systemd reports process health

ASG hosts are protected from scale-in. Before replacement, the drain script
stops local autoscaling, waits for every worker to become idle, stops workers,
then removes scale-in protection.

## State model

Self-hosted worker disks are customer-owned and are not restored by Cursor.

- Kubernetes starts from a fresh clone on ephemeral storage.
- EC2 resets the workspace before a worker registers.
- Follow-ups can reuse the workspace only while the same worker remains claimed.
- Git commits/pushes and external artifact systems are the durable checkpoints.

## Deployment tiers

Shared EKS is appropriate for one organizational trust boundary with separate
namespaces, identities, policies, quotas, and storage.

Dedicated EKS nodes add compute and cost isolation while sharing the control
plane.

Dedicated clusters or accounts are required when isolation must survive
namespace or cluster-administrator compromise, or when regulatory and audit
boundaries demand separate infrastructure.
