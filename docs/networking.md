# Networking

Workers need **outbound HTTPS only**. No public worker IPs, inbound firewall
rules, or inbound VPN for Cursor.

## Cursor destinations

Allow these hosts on port 443 for current self-hosted workers (confirm with
Cursor if your network controls reject them after a product change):

| Purpose | Host |
| --- | --- |
| Runtime API | `api2.cursor.sh` |
| Runtime API (direct) | `api2direct.cursor.sh` |
| Artifact uploads | `cloud-agent-artifacts.s3.us-east-1.amazonaws.com` |
| Installer / updates | `cursor.com`, `downloads.cursor.com` |

Also allow your SCM host, package and container registries, AWS APIs your
deployment uses, approved internal services (including MCP), and your
observability stack.

Blocking the artifact host disables artifact uploads and related previews. It
does not stop the core agent session. Prefer the exact artifact hostname over
`*.s3.us-east-1.amazonaws.com`, which opens every bucket in the region.

## Enforcement

The example NetworkPolicy allows DNS and TCP 443. That is a protocol baseline,
not a domain allowlist. Security groups and standard NetworkPolicy cannot
express FQDNs. Enforce destinations with an egress proxy, AWS Network Firewall
(or equivalent), a CNI with FQDN policy, a mesh egress gateway, or private
endpoints plus tight routing.

EC2 HTTPS egress defaults to `0.0.0.0/0` for the same reason; DNS stays limited
to the VPC CIDR. Route production HTTPS through your approved egress control.

## Local management ports

Workers expose `/healthz`, `/readyz`, and `/metrics` on port **8080**.

- **EKS:** no Service/Ingress is required. The baseline policy allows port 8080
  for kubelet probes; tighten scrape sources with your CNI when you can.
- **EC2:** management ports bind to localhost. No inbound security-group rules.
  Admin via SSM Session Manager.

## Service mesh

Optional. If you already run a mesh, validate long-lived outbound HTTP/2,
token refresh, artifact uploads, SCM/registry access, and MCP to internal
services. The controller mounts the short-lived Cursor token only into the
named worker container, not into injected sidecars.
