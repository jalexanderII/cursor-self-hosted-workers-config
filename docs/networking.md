# Networking

Self-hosted workers require outbound connectivity only. Cursor does not require
public worker IPs, inbound firewall rules, or inbound VPN tunnels.

## Required destinations

Runtime:

- `api2.cursor.sh`
- `api2direct.cursor.sh`

Artifact uploads:

- `cloud-agent-artifacts.s3.us-east-1.amazonaws.com`

Installation and updates:

- `cursor.com`
- `downloads.cursor.com`

Workload-specific destinations:

- the configured SCM host
- package and container registries
- AWS APIs used by the deployment
- approved internal APIs, databases, and command/stdio MCP endpoints
- observability and security services

Blocking the artifact host disables artifact uploads and related previews. It
does not stop the core agent session.

## Egress enforcement

The portable Kubernetes NetworkPolicy permits DNS and outbound TCP 443. This is
a protocol-level baseline, not a domain allowlist.

Standard Kubernetes NetworkPolicy and EC2 security groups cannot express FQDN
rules. Enforce destination-level policy with one of:

- corporate egress proxy
- AWS Network Firewall or equivalent
- Cilium/another CNI with supported FQDN policy
- service-mesh egress gateway
- private endpoints plus tightly scoped routing

Do not allow `*.s3.us-east-1.amazonaws.com` when an exact artifact hostname rule
is possible. That wildcard permits egress to every S3 bucket in the region.

## Ingress

Worker management endpoints run on port 8080:

- `/healthz`
- `/readyz`
- `/metrics`

No application ingress is required. The baseline policy permits only port 8080
so kubelet probes work across common CNI implementations. Restrict metrics
scraping further with CNI-specific source selectors where supported.

EC2 binds management endpoints to localhost and has no inbound security-group
rules. Administration uses SSM Session Manager.

## DNS

EC2 DNS egress is limited to the selected VPC CIDR. HTTPS egress remains
configurable and defaults to `0.0.0.0/0` because security groups cannot enforce
the required hostnames. Production deployments should route it through an
enterprise egress control.

## Service mesh

A service mesh is not required. Existing meshes may provide internal mTLS,
centralized egress, and telemetry, but they add failure modes.

Validate:

- long-lived outbound HTTP/2 connections
- token rotation and reconnection
- artifact uploads
- SCM/package-registry access
- command/stdio MCP access to internal services

The controller mounts the short-lived Cursor token only into the named worker
container, not injected sidecars.
