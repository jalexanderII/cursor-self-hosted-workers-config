# Contributing

## Principles

- Keep EKS and EC2 independently usable.
- Prefer portable secure defaults and optional platform integrations.
- Do not claim that pools, labels, namespaces, or shared hosts provide hard
  tenant isolation.
- Do not add secret values, customer data, or generated Terraform state.
- Preserve active-session safety during rollout and scale-down.
- Verify behavior against current public Cursor and AWS documentation.

## Local checks

Install the pinned core tools and run:

```bash
mise install
mise test
mise lint
mise format-dryrun
```

`mise lint` performs backend-free Terraform initialization and validation. It
does not run plans, inspect live state, or require AWS/Kubernetes credentials.

## Pull requests

Describe:

- security and compatibility impact
- changed defaults and migration steps
- validation performed
- whether EKS, EC2, or both are affected
- any manual disposable-infrastructure test still required

Do not commit generated `rendered/` manifests, `.terraform/`, plans, state, or
local `.env` files.

## Release-sensitive changes

For controller, EKS, Terraform, base-image, or Cursor CLI updates:

1. Confirm the version is supported.
2. Update documentation and examples together.
3. Use immutable image tags.
4. Test upgrade and rollback.
5. Record breaking changes in the migration notes.
