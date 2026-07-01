# FinOps and chargeback

Cursor inference/product costs and customer infrastructure costs are separate
allocation pipelines.

## Cursor usage

Use the Cursor dashboard, CSV exports, Billing Groups, and Admin API usage
events. The filtered usage-events API supports dimensions including:

- `hostingType`, including `SELF_HOSTED_POOL`
- initiating user or `serviceAccountId`
- Cloud Agent and automation identifiers
- model, tokens, and per-event charged cents

`serviceAccountId` identifies the principal that initiated a request. It should
not be assumed to identify the service account used only to authenticate a
worker pool.

Billing Groups support reporting, budgeting, and chargeback organization. They
do not enforce infrastructure isolation or Kubernetes spend limits.

## Customer infrastructure

Cursor does not meter customer-owned EC2/EKS compute, EBS/EFS, NAT, ECR,
network, logging, or cache costs.

Use AWS CUR with your existing tooling, such as Cloudability, Kubecost, OpenCost,
or equivalent. There is no native Cursor-specific Cloudability integration.

## Canonical allocation dimensions

Use the same vocabulary across Cursor pools, Kubernetes labels, and AWS tags:

- `Application` / `application`
- `Deployment` / `deployment`
- `Environment` / `environment`
- `Service` / `service`
- `Owner` / `owner`
- `CostCenter` / `cost-center`
- `Project` / `project`
- `cursor-pool`

Apply AWS tags to node groups, EC2 instances, EBS/EFS, ECR, NAT gateways,
logging resources, and supporting network resources. Apply Kubernetes labels to
namespaces and worker pod templates.

Cursor worker labels are routing metadata. Kubernetes labels and AWS tags are
the infrastructure allocation source of truth.

## Reconciliation model

Maintain a controlled mapping between:

- Cursor team and Billing Group
- initiating user/service account
- repository or project
- Cursor pool
- Kubernetes namespace/WorkerDeployment or EC2 ASG
- cost center and owner

Use worker and controller metrics for capacity/utilization, but use AWS and
Kubernetes cost data for actual infrastructure chargeback.

## Capacity guardrails

The default Cursor limit is 50 workers per team unless a larger deployment is
approved. Terraform checks the configured EC2 maximum against that default.

For Kubernetes, `readyReplicas` is only the idle floor. Total pods equal busy
workers plus the idle floor, so ResourceQuota must be sized for expected peak
concurrency and should remain below the approved Cursor worker limit.
