# Security

Treat self-hosted workers like privileged CI runners on potentially adversarial
repository content. They can run shell, edit files, use local MCP, and reach
whatever their network and credentials allow.

## Trust boundary

Cursor runs the agent loop and inference. Workers run in your environment and
connect outbound over HTTPS.

May leave your network in normal operation:

- file contents selected for inference
- tool output, diffs, and command results
- artifacts (for example screenshots or logs)
- worker metadata used for routing and health

Clones, caches, and customer-managed secrets stay on the worker unless a
command, tool, or dependency transmits them. Privacy Mode governs Cursor's use
of code data; it does not replace identity, sandboxing, or egress controls on your
side.

## Isolation

Pools, Cursor labels, Kubernetes namespaces, and Linux users are labels and
scheduling boundaries, not hard multi-tenant security boundaries.

For a shared cluster, keep one organizational trust boundary and give each
security or chargeback domain its own namespace, `WorkerDeployment`, Cursor
service account, Kubernetes ServiceAccount / IAM role, secrets, NetworkPolicy,
and quota (dedicated nodes when practical).

Use a dedicated cluster or AWS account when administrators differ, namespace
compromise must not affect another tenant, or shared kernel / IAM / storage risk
is unacceptable.

On EC2, multi-slot hosts share kernel, instance profile, and git objects.
Default is one worker per host.

## Credentials

**Kubernetes:** a labeled Secret holds the Cursor service account API key. The
controller exchanges it for short-lived tokens mounted at
`/var/run/cursor/token` for the worker container only. The CLI rereads the file
on reconnect so tokens can rotate without restarting the pod.

**EC2:** the service account key is read from Secrets Manager at process start
and is available to that process. Use a dedicated service account per trust
domain.

An agent can use any credential available to its worker. Scope credentials
narrowly, prefer file mounts over env vars, prefer workload identity over static
cloud keys, and keep audit logs at SCM, CloudTrail, and registries.

Terraform creates secret *containers*, not values:

```bash
CURSOR_API_KEY=... make put-secret-cursor-api-key
SCM_TOKEN=... make put-secret-scm-token
# Kubernetes:
CURSOR_API_KEY=... make kube-create-api-key-secret
SCM_TOKEN=... make kube-create-scm-secret
```

Helpers read from stdin so values are not process arguments. The External
Secrets example assumes your platform already runs ESO; this repo does not
install it.

## IAM and hosts

EC2 roles grant only: Secrets Manager reads for configured ARNs, CloudWatch
metrics in the configured namespace, SSM Session Manager, and removing that
instance's own scale-in protection after drain. Code on the host can still use
that role; isolate untrusted work in separate accounts or fleets if needed.

Kubernetes workers set `automountServiceAccountToken: false`. Add IRSA or Pod
Identity only when the workload needs AWS APIs.

Baseline pod settings: restricted Pod Security, non-root, `RuntimeDefault`
seccomp, no privilege escalation, dropped capabilities, bounded ephemeral
storage. EC2 baseline: IMDSv2, no inbound security-group rules, SSM admin,
encrypted EBS, scale-in protection, systemd hardening.

Destination allowlists: see [`networking.md`](networking.md). Security groups and
portable NetworkPolicy cannot express FQDNs; use a proxy, network firewall, CNI
FQDN policy, or mesh egress gateway.

## Data and response

Kubernetes workspaces are `emptyDir`. Do not share an RWX volume across trust
domains. EC2 defaults to `git clean -fdx` before registration.

On incident: rotate Cursor and SCM credentials at source, update Secrets Manager
/ synced K8s secrets, drain EC2 hosts or set `readyReplicas: 0`, revoke old
credentials, and retain centralized logs before tearing infrastructure down.
