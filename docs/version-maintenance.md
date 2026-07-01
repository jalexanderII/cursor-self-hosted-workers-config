# Version and supply-chain maintenance

## Pinned components

- Terraform: use a supported release (examples target 1.15.x)
- EKS minor version: greenfield Terraform example
- Cursor controller chart and image: `terraform/modules/eks-workers/main.tf`
- Terraform providers: committed lock files
- Worker image: immutable ECR tag or digest supplied by the operator

The Cursor CLI installer is the supported public distribution mechanism. The
image and EC2 bootstrap download it over TLS. Regulated environments should set
`CURSOR_INSTALL_URL` to an internally mirrored, reviewed artifact.

## Review cadence

Monthly:

- check controller and Cursor self-hosted documentation
- review base-image and ECR vulnerability findings
- review Terraform provider and module versions in the examples you maintain
- rebuild the worker image even when application dependencies have not changed

Before the EKS standard-support deadline:

1. verify controller and add-on compatibility
2. test the next minor version in a disposable cluster
3. update control plane one minor at a time
4. update add-ons and managed nodes
5. roll the worker image and run a test agent

## Promotion

- build with a unique release or commit tag
- capture SBOM and provenance
- review vulnerability results
- record the image digest
- promote the exact digest between environments
- never overwrite a production tag

## EC2 AMIs

Production requires an explicit reviewed `ec2_ami_id`. Do not rely on
`most_recent` in production. Build or select a replacement AMI, validate
bootstrap, drain old hosts, and then start an explicit instance refresh.

EC2 bootstrap assets are gzip-compressed into Launch Template user data. The EC2
module checks the compressed payload against the 16 KiB decoded limit. If it
grows beyond that, move tooling into the AMI or an authenticated, versioned
artifact store.

## Rollback

Keep previous controller versions, image digests, Launch Template versions, and
Terraform source available. Roll back declarative configuration first, then
drain and replace affected capacity without interrupting active sessions.
