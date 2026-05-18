# Cursor Self-Hosted Workers on EC2

This repo contains the scripts and systemd units for running Cursor self-hosted cloud workers on a single EC2 instance.

The setup uses:

- AWS Secrets Manager for the Cursor service account key and GitHub PAT
- systemd for worker lifecycle management
- git worktrees for multiple concurrent workers on one repo
- a local scale-up-only autoscaler based on each worker's `/readyz` endpoint
- CloudWatch metrics publishing for local worker health

## Layout

```text
bin/
  git-credential-github-secretsmanager # fetches GitHub credentials from AWS Secrets Manager
  cursor-worker-start              # starts one worker and cleans its worktree first
  cursor-workers-reconcile         # creates worktrees and systemd units without restarting active workers
  cursor-workers-autoscale         # adds workers when local idle capacity drops below threshold
  cursor-workers-publish-metrics   # publishes local worker counts to CloudWatch

systemd/
  cursor-workers-autoscale.service
  cursor-workers-autoscale.timer
  cursor-workers-metrics.service
  cursor-workers-metrics.timer

examples/
  env.example
  labels.json
  workers.example.json
```

## Required AWS Secrets

Create these secrets in the same AWS region as the EC2 instance:

```text
cursor/self-hosted-workers/cursor-api-key
cursor/self-hosted-workers/github-pat
```

The EC2 instance profile must allow:

```text
secretsmanager:GetSecretValue
```

for those secret ARNs.

## Install

Install dependencies:

```bash
sudo apt-get update
sudo apt-get install -y git curl ca-certificates jq awscli
```

Install the Cursor agent CLI:

```bash
curl -fsSL "https://www.cursor.com/install?channel=lab" | bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
agent --version
```

Install scripts:

```bash
sudo install -m 755 bin/git-credential-github-secretsmanager /usr/local/bin/git-credential-github-secretsmanager
sudo install -m 755 bin/cursor-worker-start /usr/local/bin/cursor-worker-start
sudo install -m 755 bin/cursor-workers-reconcile /usr/local/bin/cursor-workers-reconcile
sudo install -m 755 bin/cursor-workers-autoscale /usr/local/bin/cursor-workers-autoscale
sudo install -m 755 bin/cursor-workers-publish-metrics /usr/local/bin/cursor-workers-publish-metrics
```

Install config:

```bash
sudo mkdir -p /etc/cursor-workers
sudo install -m 640 examples/env.example /etc/cursor-workers/env
sudo install -m 644 examples/labels.json /etc/cursor-workers/labels.json
sudo install -m 644 examples/workers.example.json /etc/cursor-workers/workers.json
```

Edit `/etc/cursor-workers/env` and `/etc/cursor-workers/workers.json` for the target AWS region, secret names, OS user, agent path, repo, branch, worker count, and ports.

Key customization values live in `/etc/cursor-workers/env`:

```bash
AWS_REGION=us-east-1
CURSOR_API_SECRET_ID=cursor/self-hosted-workers/cursor-api-key
GITHUB_PAT_SECRET_ID=cursor/self-hosted-workers/github-pat
GITHUB_HOST=github.com
CURSOR_WORKER_POOL_NAME=default
CURSOR_WORKER_IDLE_RELEASE_TIMEOUT=900
CURSOR_WORKER_USER=ubuntu
CURSOR_AGENT_BIN=/home/ubuntu/.local/bin/agent
CURSOR_WORKERS_MANIFEST=/etc/cursor-workers/workers.json
CURSOR_WORKERS_LABELS_FILE=/etc/cursor-workers/labels.json
CURSOR_WORKERS_BASE_DIR=/opt/cursor-workers/base
CURSOR_WORKER_CLEAN_MODE=normal
CURSOR_AUTOSCALE_MIN_IDLE=1
CURSOR_AUTOSCALE_SCALE_STEP=2
CURSOR_AUTOSCALE_MAX_LOCAL_WORKERS=15
CURSOR_METRICS_NAMESPACE=Cursor/SelfHostedWorkers
```

Install the GitHub credential helper:

```bash
sudo install -m 755 bin/git-credential-github-secretsmanager /usr/local/bin/git-credential-github-secretsmanager
git config --global credential.helper /usr/local/bin/git-credential-github-secretsmanager
rm -f ~/.git-credentials
```

Run reconcile:

```bash
sudo /usr/local/bin/cursor-workers-reconcile
```

## Enable Timers

Install timer units:

```bash
sudo install -m 644 systemd/cursor-workers-autoscale.service /etc/systemd/system/cursor-workers-autoscale.service
sudo install -m 644 systemd/cursor-workers-autoscale.timer /etc/systemd/system/cursor-workers-autoscale.timer
sudo install -m 644 systemd/cursor-workers-metrics.service /etc/systemd/system/cursor-workers-metrics.service
sudo install -m 644 systemd/cursor-workers-metrics.timer /etc/systemd/system/cursor-workers-metrics.timer
sudo systemctl daemon-reload
sudo systemctl enable --now cursor-workers-autoscale.timer
sudo systemctl enable --now cursor-workers-metrics.timer
```

## Worker Lifecycle

Each worker is one `agent worker start --pool` process and one git working directory.

Before a worker registers, `cursor-worker-start` resets its worktree:

```bash
git fetch origin --prune
git reset --hard origin/<branch>
git clean -fd
```

That ensures the next session starts from the latest remote branch after the previous session releases and systemd restarts the worker.

## Autoscaling

`cursor-workers-autoscale` scales up only. Defaults are configured in `/etc/cursor-workers/env`:

```text
MIN_IDLE=1
SCALE_STEP=2
MAX_LOCAL_WORKERS=15
```

It reads `/etc/cursor-workers/workers.json`, checks each local `/readyz` endpoint, appends workers if idle capacity is too low, then calls `cursor-workers-reconcile`.

There is intentionally no scale-down logic.

## Operations

Check workers:

```bash
for port in $(jq -r '.workers[].managementPort' /etc/cursor-workers/workers.json); do
  echo -n "$port "
  curl -s "http://127.0.0.1:${port}/readyz"
  echo
done
```

Run non-disruptive reconcile:

```bash
sudo /usr/local/bin/cursor-workers-reconcile
```

View worker logs:

```bash
sudo journalctl -u 'cursor-worker-*.service' -f
```

View autoscaler logs:

```bash
sudo journalctl -u cursor-workers-autoscale.service -n 100 --no-pager
```

View metrics publisher logs:

```bash
sudo journalctl -u cursor-workers-metrics.service -n 100 --no-pager
```

## Notes

- Do not commit real API keys, GitHub tokens, `.pem` files, or `/etc/cursor-worker/api-key`.
- The Cursor service account key is used by worker processes. End users do not need this key.
- Pool names and labels are routing/capacity metadata, not a security boundary.
- Use separate Cursor teams, GitHub integrations, service accounts, and fleets for hard isolation between groups or customers.
- The public private-workers API exposes worker names, repo metadata, service account IDs, and usage state. It should not be treated as an authoritative source for custom worker labels.
- The local autoscaler intentionally scales up only. To reduce workers, manually remove extra manifest entries and stop/disable the corresponding systemd services after confirming they are idle.
