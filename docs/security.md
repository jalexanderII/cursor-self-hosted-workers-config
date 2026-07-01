# Security model

Self-hosted Cloud Agent workers execute shell commands, edit files, run local
MCP servers, and access resources available from their environment. Treat them
like privileged CI runners operating on potentially adversarial repository
content.

## Trust boundary

Cursor hosts the agent loop, orchestration, inference, and product experience.
Workers connect outbound over HTTPS and execute tools in customer infrastructure.

The following may leave the customer network as part of normal operation:

- selected file contents sent for inference
- tool output, diffs, and command results returned to the agent loop
- artifacts such as screenshots, videos, and log references
- worker metadata needed for routing and health

Repository clones, local caches, and customer-managed secrets remain on the
worker unless a command, tool, integration, or compromised dependency transmits
them. Privacy Mode controls Cursor's use of code data; it does not replace
customer-side identity, sandboxing, or egress controls.

## Isolation model

Pool names, Cursor labels, Kubernetes labels, namespaces, and Linux users are
not hard isolation boundaries.

Use a shared EKS cluster only for workloads inside one organizational trust
boundary. Give each security or chargeback domain its own namespace,
`WorkerDeployment`, Cursor service account, Kubernetes ServiceAccount, IAM role,
secret scope, NetworkPolicy, quota, and preferably dedicated nodes.

Use dedicated clusters or AWS accounts when:

- administrators differ
- namespace compromise must not affect another tenant
- regulated workloads require a clean audit boundary
- shared kernel, node, IAM, or storage risk is unacceptable
- persistent storage cannot be strongly partitioned

EC2 multi-slot mode shares one kernel, instance profile, Linux identity, and git
object database. The production default is one worker per host. Multi-slot mode
is an explicit density optimization for mutually trusted workloads.

## Worker authentication

Kubernetes uses the official controller authentication flow:

1. A labeled, namespaced Secret contains the Cursor service account API key.
2. The controller exchanges it for short-lived worker tokens.
3. Only the designated worker container receives `/var/run/cursor/token`.
4. The CLI rereads the file during reconnection so the controller can rotate it.

EC2 uses the service account key from Secrets Manager at worker-process start.
It is not written to disk or passed as a command argument, but it is available
to the worker process. Use a dedicated service account per trust domain.

## Workload and SCM secrets

An agent can use any credential available to its worker. No redaction layer can
make a credential inaccessible to the same process that must consume it.

Controls:

- use short-lived, narrowly scoped credentials
- use separate credentials per repo, pool, and environment
- prefer workload identity over static AWS keys
- mount secrets read-only and avoid environment variables where supported
- restrict network destinations and repository permissions
- retain CloudTrail, SCM, package registry, and application audit logs
- require branch protection and review for privileged repositories

Terraform creates secret containers and references, not values. Write values
only through a dedicated secret-management workflow:

```bash
CURSOR_API_KEY=... make put-secret-cursor-api-key
SCM_TOKEN=... make put-secret-scm-token
```

For Kubernetes:

```bash
CURSOR_API_KEY=... make kube-create-api-key-secret
SCM_TOKEN=... make kube-create-scm-secret
```

The helper scripts read values from stdin and use protected temporary files, so
the values do not appear in process arguments.

The optional External Secrets example assumes your platform team already owns
the operator and `SecretStore`. This repository does not install them.

## IAM

EC2 receives only:

- read access to configured Secrets Manager ARNs
- CloudWatch metric publishing to the configured namespace
- SSM Session Manager access
- permission to remove its own ASG scale-in protection after a successful drain

This instance role is still reachable by code running on the host. For untrusted
repositories, use separate AWS accounts/fleets or an execution model that blocks
workload access to host credentials.

Kubernetes workers do not need a Kubernetes API token. The ServiceAccount has
`automountServiceAccountToken: false`. Add IRSA or EKS Pod Identity only when
the workload actually needs AWS APIs, and scope the role to that pool.

## Pod and host protections

The Kubernetes baseline enforces restricted Pod Security, a non-root UID,
`RuntimeDefault` seccomp, no privilege escalation, and dropped capabilities.
Workspaces and temporary files use bounded ephemeral volumes.

The EC2 baseline requires IMDSv2, has no inbound security-group rules, uses SSM
for administration, encrypts EBS, protects hosts from scale-in, and adds systemd
process/filesystem hardening. Review systemd restrictions against repo-specific
build tools before tightening them further.

## Network

See [`networking.md`](networking.md). Security groups and portable Kubernetes
NetworkPolicy cannot enforce domain allowlists. Use an egress proxy, firewall,
CNI FQDN policy, or service-mesh gateway for destination-level controls.

## Persistent data

Kubernetes workspaces are ephemeral `emptyDir` volumes. Do not add a shared RWX
workspace volume across trust domains. If persistent caches are required, use
separate credentials, prefixes/access points, encryption keys, and quotas.

EC2 workspaces are reset with `git clean -fdx` before registration. Durable
state belongs in Git, artifact stores, package caches, or other external systems.

## Rotation and incident response

- Rotate the Cursor key and SCM token at their source.
- Update Secrets Manager or the synchronized Kubernetes Secret.
- Confirm controller token refresh or restart idle workers.
- Revoke old credentials immediately.
- Drain affected EC2 hosts or set `readyReplicas: 0` for an affected EKS pool.
- Preserve centralized logs and audit records before deleting infrastructure.

Never claim that self-hosted workers provide automatic workspace backup,
credential non-disclosure, or hard tenant isolation without the corresponding
customer platform controls.
