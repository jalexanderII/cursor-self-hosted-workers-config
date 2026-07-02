# Cost allocation

Cursor product usage and customer-owned infrastructure are separate cost streams.

## Cursor usage

Use the Cursor dashboard, exports, Billing Groups, and Admin API usage events.
Self-hosted pool traffic is identifiable (for example `hostingType` includes
`SELF_HOSTED_POOL`). Events also carry initiating user or service account,
model/token dimensions, and charged amounts.

`serviceAccountId` on a usage event is the **initiator** of the request. It is
not necessarily the service account that authenticates the worker pool.

Billing Groups help organize reporting and chargeback. They do not enforce
Kubernetes or AWS spending limits.

## Your infrastructure

Cursor does not meter your EC2/EKS, storage, NAT, ECR, or logging costs. Use AWS
CUR and your existing cost tools (Cloudability, Kubecost, OpenCost, etc.). There
is no Cursor-specific Cloudability connector.

## Tags and labels

Use the same dimensions across Cursor pools, Kubernetes labels, and AWS tags
(for example `environment`, `owner`, `cost-center`, `cursor-pool`). Tag node
groups, instances, volumes, NAT, ECR, and logging resources. Label namespaces
and worker pods.

Cursor worker labels are routing metadata. AWS tags and Kubernetes labels are
what your FinOps tools should join on.

Map, under change control: Cursor team / Billing Group → pool →
namespace/`WorkerDeployment` or ASG → cost center.

Use worker metrics for capacity; use AWS/Kubernetes cost data for dollars.

## Capacity

Default Cursor limit is **50 workers per team** unless a larger fleet is
approved. On EC2, Terraform checks configured maximums against that default. On
EKS, size ResourceQuota for peak busy pods **plus** the idle `readyReplicas`
floor, and stay under the approved worker limit.
