# Architecture

```text
User or automation
       |
       v
Cursor cloud: agent loop, orchestration, inference, routing, UI
       |
       | long-lived outbound HTTPS (tool requests and results)
       v
Customer worker: repository, shell, filesystem, local MCP, private services
```

Workers dial out. Cursor does not require inbound access to your network.

| Cursor owns | You own |
| --- | --- |
| Agent planning and inference | Worker images, filesystem, and cleanup |
| Run orchestration and routing | Compute capacity (EKS or EC2) |
| Product UI and artifact storage | SCM and workload credentials |
| Usage telemetry on Cursor's side | Network policy, logging, recovery |

## Kubernetes lifecycle

`readyReplicas` is an **idle floor**, not a maximum.

1. Pod starts and registers.
2. `/readyz` is HTTP 200 while connected and idle.
3. Cursor claims the worker; `/readyz` becomes non-200.
4. Controller starts another pod to restore the idle floor.
5. Busy pods survive scale-down and rolling updates.
6. After the session and idle timeout, the process exits and the pod is replaced.

Use the Cursor controller for pods. Use Cluster Autoscaler, Karpenter, or EKS
Auto Mode for nodes. Do not attach an HPA to controller-managed worker pods.

## EC2 lifecycle

Each systemd unit is one worker and one workspace. Default is one unit per host.

Local autoscaling uses only that host's interfaces:

- `/readyz` HTTP 200 → connected and idle
- `/metrics` → connection / active-session gauges
- systemd → process health

ASG instances are protected from scale-in. `cursor-workers-drain` stops local
autoscaling, waits until every worker is idle, stops workers, then removes
protection.

## State

Worker disks are yours. Cursor does not back them up or restore them.

- Kubernetes: fresh clone on ephemeral storage each pod.
- EC2: workspace reset before the worker registers.
- Durable work is Git (and any artifact store you require). Follow-ups reuse a
  workspace only while the same worker remains claimed.

## Isolation tiers

| Tier | Use when |
| --- | --- |
| Shared EKS, separate namespaces | One org trust boundary; separate identities, secrets, quotas |
| Dedicated node pools | Need compute isolation; still share control plane |
| Dedicated cluster or account | Hostile/regulatory tenants; must survive namespace or cluster-admin compromise |
