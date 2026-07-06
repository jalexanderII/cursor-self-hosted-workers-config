# Multi-team EKS: one controller, many isolated pools

This example shows the pattern to use when a **central platform team runs one
worker-set controller** and each product/team gets its **own isolated worker
pool** for chargeback and blast-radius separation.

It builds on [`../eks-existing-cluster`](../eks-existing-cluster) but instead of
a single pool it provisions:

- **one cluster-wide controller** (in `cursord-system`) that watches all
  namespaces and installs the cluster-scoped `WorkerDeployment` CRD once, and
- **one namespace + `WorkerDeployment` per team**, each with its own Cursor
  pool, Kubernetes ServiceAccount, NetworkPolicy, ResourceQuota, and cost
  labels.

```
                 worker-set-controller (cursord-system, cluster-wide)
                          |
   +----------------------+----------------------+
   |                      |                       |
 cursor-payments      cursor-claims           cursor-<team>
 WorkerDeployment     WorkerDeployment        WorkerDeployment
 pool=payments-eks    pool=claims-eks         pool=<team>-eks
```

## When to use this vs the single-pool example

- **Single pool** ([`../eks-existing-cluster`](../eks-existing-cluster)): one
  team/trust boundary, controller runs in single-namespace RBAC mode.
- **Multi-team (this example):** many teams share the cluster, each needs its
  own pool, egress rules, and cost attribution. See the isolation guidance in
  [`../../../docs/security.md`](../../../docs/security.md) and the FinOps model
  in [`../../../docs/finops.md`](../../../docs/finops.md).

Pool names, labels, and namespaces are routing and scheduling boundaries, not
hard multi-tenant security boundaries. When administrators differ or a namespace
compromise must not reach another tenant, use a dedicated cluster or account.

## Scope of this example

To stay focused on the multi-pool pattern, this example does **not** manage ECR
or AWS Secrets Manager. It assumes:

- the worker image is already built and pushed (set `worker_image`), and
- each team's Kubernetes secrets already exist in its namespace: the Cursor API
  key (`cursor_api_key_secret_name`) and the SCM token
  (`scm_token_secret_name_k8s`).

See [`../../../docs/aws-eks-existing-cluster.md`](../../../docs/aws-eks-existing-cluster.md)
for the secret-creation Make targets, and
[`../../../kube/integrations/external-secrets/external-secrets.example.yaml`](../../../kube/integrations/external-secrets/external-secrets.example.yaml)
for syncing secrets from an enterprise secret manager per namespace.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# edit worker_image and the teams map

terraform init
terraform plan
terraform apply
```

`apply` installs the shared controller and writes one rendered manifest per team
under `rendered/<team>-workers.yaml`. Create each team's Kubernetes secrets,
then apply the manifests:

```bash
# per team, after its api-key and scm secrets exist in the namespace
kubectl apply -f rendered/payments-workers.yaml
kubectl apply -f rendered/claims-workers.yaml

kubectl get wd -A
```

## Adding a team

Add an entry to the `teams` map and re-apply. A new namespace, pool, and
`WorkerDeployment` are created; the shared controller picks it up. Create that
team's secrets before applying its rendered manifest.

## Cost allocation

Each team carries `team`, `cost-center`, and `owner` labels on its namespace and
worker pods. Mirror these as AWS tags on the nodes that run each namespace so
Cloudability/Kubecost/OpenCost can attribute compute per team, then join with
Cursor usage from the Admin API (`hostingType = SELF_HOSTED_POOL`). See
[`../../../docs/finops.md`](../../../docs/finops.md).
