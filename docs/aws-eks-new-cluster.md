# New EKS cluster deployment

This path creates a baseline EKS cluster and ECR repository with Terraform. It
does not install workers directly. After the cluster exists, use the existing
cluster runbook to install the Cursor controller and render the WorkerDeployment.

The split is intentional. Kubernetes providers need a working kubeconfig and the
Cursor `WorkerDeployment` CRD needs the controller installed before the worker
manifest is applied.

## Prerequisites

- AWS credentials with VPC, EKS, IAM, CloudWatch Logs, and ECR permissions.
- Terraform 1.6 or newer.
- `kubectl`, Helm 3, Docker, and AWS CLI.

## Configure

Copy the example vars if you prefer a file over `.env`:

```bash
cp terraform/examples/eks-new-cluster/terraform.tfvars.example \
  terraform/examples/eks-new-cluster/terraform.tfvars
```

Edit:

```hcl
eks_cluster_name        = "cursor-workers"
eks_vpc_cidr            = "10.40.0.0/16"
eks_node_instance_types = ["m6i.xlarge"]
eks_node_desired_size   = 3
eks_node_max_size       = 10
```

The module creates private worker subnets and NAT egress. Set
`eks_single_nat_gateway = true` only when cost matters more than AZ-level NAT
resilience.

## Deploy

```bash
make eks-cluster-init
make eks-cluster-plan
make eks-cluster-apply
```

Configure kubectl using the Terraform output:

```bash
terraform -chdir=terraform/examples/eks-new-cluster output update_kubeconfig_command
```

Then build and push the worker image:

```bash
make ecr-build-push
```

## Continue with workers

After kubeconfig points at the new cluster, follow
[`aws-eks-existing-cluster.md`](aws-eks-existing-cluster.md).

## Node scaling

The managed node group has a min, desired, and max size. That is node capacity,
not Cursor worker replica scaling. If worker pods are pending with insufficient
CPU or memory, either:

- increase node group desired/max size
- install Cluster Autoscaler or Karpenter
- lower `worker_ready_replicas`
- lower pod resource requests only if your repo workload can tolerate it

## Cleanup

Destroy workers first if you installed them, then destroy the cluster:

```bash
terraform -chdir=terraform/examples/eks-existing-cluster destroy
terraform -chdir=terraform/examples/eks-new-cluster destroy
```
