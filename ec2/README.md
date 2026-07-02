# EC2 systemd workers

Scripts and units that run Cursor Self-Hosted pool workers on a Linux host with
systemd.

Preferred path: [`../docs/aws-ec2-asg.md`](../docs/aws-ec2-asg.md). Terraform
installs these binaries into the AMI / launch template user data and scales them
with an ASG.

## Layout

```text
bin/
  cursor-worker-start                 Start one worker; reset workspace first
  cursor-workers-reconcile            Create worktrees and systemd units
  cursor-workers-autoscale            Scale local slots from /readyz
  cursor-workers-publish-metrics      Publish local counts to CloudWatch
  cursor-workers-drain                Safe host drain before scale-in
  git-credential-scm-secretsmanager   SCM token helper (any HTTPS host)

systemd/                              Timers for autoscale and metrics
examples/                             Sample workers.json, labels, repo-env map
```

## Behavior that matters

- Default production density is **one worker per host**. Multi-slot mode shares
  kernel, instance profile, and git objects; use it only for mutually trusted
  workloads.
- Before registration, `cursor-worker-start` resets the worktree
  (`git clean -fdx` by default) so prior sessions do not leak files.
- Autoscaling and metrics use only this host's `/readyz` and `/metrics`. Do not
  drive instance-local decisions from team-wide capacity APIs; those counts
  include other fleets.
- Hosts are ASG scale-in protected. Run `cursor-workers-drain` (via SSM) before
  reducing capacity or starting an instance refresh. A failed drain leaves
  protection in place.
- Secrets come from Secrets Manager at process start. Do not put API keys or SCM
  tokens in git, user data as plaintext, or process arguments.

## Config files on the host

```text
/etc/cursor-workers/env            Shared settings and secret IDs
/etc/cursor-workers/workers.json   Worker slots (name, dir, ports)
/etc/cursor-workers/labels.json    Optional Cursor worker labels
```

Examples live under `examples/`. Terraform templates generate the production
copies from `terraform/templates/`.

## Manual install (lab / custom AMI)

Use this only when you are baking an AMI or debugging outside Terraform:

1. Install the `bin/` scripts to `/usr/local/bin` and the systemd units.
2. Create `/etc/cursor-workers/{env,workers.json}` from the examples.
3. Configure the SCM credential helper and Secrets Manager secret IDs.
4. Run `cursor-workers-reconcile`, then enable the autoscale and metrics timers.

Egress requirements are in [`../docs/networking.md`](../docs/networking.md).
Day-2 operations are in [`../docs/operations.md`](../docs/operations.md).
