# Cursor Self-Hosted Workers on EC2

This template runs Cursor self-hosted pool workers on a single EC2 instance using systemd.

The setup uses:

- AWS Secrets Manager for the Cursor service account key and GitHub PAT
- optional AWS Secrets Manager hydration for repo-local `.env` / config files
- systemd for worker lifecycle management
- git worktrees for multiple concurrent workers on one repo
- a local autoscaler based on each worker's `/readyz` endpoint
- CloudWatch metrics publishing for local worker health

## Layout

```text
bin/
  git-credential-github-secretsmanager # fetches GitHub credentials from AWS Secrets Manager
  cursor-worker-start              # starts one worker and cleans its worktree first
  cursor-workers-reconcile         # creates worktrees and systemd units without restarting active workers
  cursor-workers-autoscale         # adds/removes workers based on local idle capacity
  cursor-workers-publish-metrics   # publishes local worker counts to CloudWatch

systemd/
  cursor-workers-autoscale.service
  cursor-workers-autoscale.timer
  cursor-workers-metrics.service
  cursor-workers-metrics.timer

examples/
  cursor-workers-autoscale-team-summary.example.sh
  env.example
  labels.json
  repo-env-files.example
  workers.example.json
```

## Design Notes

- Use AWS Secrets Manager for long-lived credentials. Do not write service account keys, GitHub tokens, or repo `.env` files into git.
- Use one Secrets Manager secret per repo-local env/config file. Store the raw file body as `SecretString`; do not convert large `.env` files to JSON.
- Use git worktrees for concurrent workers on one EC2 host. Each worker needs an isolated working directory, while the host still shares git object storage efficiently.
- Reset and clean each worktree before worker registration so a released worker cannot leak dirty files into the next session.
- Use local `/readyz` endpoints for autoscaling decisions. Cursor's team summary API is useful for visibility, but it is team-wide and may include other hosts or pools.
- Scale-down is conservative: only extra idle workers above the base floor are removed, and claimed workers are never stopped.

## Required AWS Secrets

Create these secrets in the same AWS region as the EC2 instance:

```text
cursor/self-hosted-workers/cursor-api-key
cursor/self-hosted-workers/github-pat
```

Optional repo tooling secrets (API keys for services in the worker checkout, for example image generation, audio generation, private package registries, or deployment previews):

```text
cursor/self-hosted-workers/repos/YOUR_REPO/app.env
cursor/self-hosted-workers/repos/YOUR_REPO/service-a.env
```

Use one Secrets Manager secret per file to recreate in the worker checkout. Store the exact file body as the secret's raw `SecretString` / plaintext value. Do not convert large `.env` files to JSON; upload or paste them as-is.

```bash
aws secretsmanager create-secret \
  --region us-east-1 \
  --name cursor/self-hosted-workers/repos/YOUR_REPO/app.env \
  --secret-string file://app.env
```

Then create a mapping file on the EC2 host. Each line maps a repo-relative target path to the secret id containing the raw file body:

```text
app/.env cursor/self-hosted-workers/repos/YOUR_REPO/app.env
services/api/.env.production cursor/self-hosted-workers/repos/YOUR_REPO/api-production.env
```

Set `CURSOR_REPO_ENV_FILES=/etc/cursor-workers/repo-env-files` in `/etc/cursor-workers/env`. `cursor-worker-start` fetches each mapped secret after `git clean` and writes the target file into the worker worktree with mode `600`. Untracked `.env` files are removed on every worker restart, so secrets are not persisted in git; they are re-injected from Secrets Manager.

The EC2 instance profile must allow:

```text
secretsmanager:GetSecretValue
```

for those secret ARNs (and for any repo env file secrets you configure).

Example IAM statement for a repo env secret:

```json
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": "arn:aws:secretsmanager:REGION:ACCOUNT_ID:secret:cursor/self-hosted-workers/repos/YOUR_REPO/*"
}
```

Create and rotate repo env secrets with an admin AWS principal. The EC2 role only needs read access.

## Cursor Prerequisites

Before installing the EC2 worker fleet:

1. Enable self-hosted / private workers for the Cursor team.
2. Connect the Cursor GitHub integration at the team level and authorize the target repo.
3. Create a Cursor service account and store its API key in AWS Secrets Manager.
4. Create a GitHub credential for the worker host, usually a fine-grained PAT with `Contents: Read and write` for the target repo, and store it in AWS Secrets Manager.
5. Turn on the team's self-hosted pool in the Cursor Cloud Agents dashboard.

Pool names and labels are routing metadata, not a security boundary. Use separate Cursor teams, GitHub integrations, service accounts, and fleets when groups or customers need hard isolation from each other.

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
sudo install -m 644 examples/env.example /etc/cursor-workers/env
sudo install -m 644 examples/labels.json /etc/cursor-workers/labels.json
sudo install -m 644 examples/workers.example.json /etc/cursor-workers/workers.json
# Optional, only if this repo needs env/config files hydrated from Secrets Manager:
sudo install -m 644 examples/repo-env-files.example /etc/cursor-workers/repo-env-files
```

Edit `/etc/cursor-workers/env` and `/etc/cursor-workers/workers.json` for the target AWS region, secret names, OS user, agent path, repo, branch, worker count, and ports. If you install `/etc/cursor-workers/repo-env-files`, replace the example lines with real repo-relative target paths and secret ids before enabling `CURSOR_REPO_ENV_FILES`.

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
# Optional. Enable only after /etc/cursor-workers/repo-env-files contains real mappings.
# CURSOR_REPO_ENV_FILES=/etc/cursor-workers/repo-env-files
CURSOR_WORKER_CLEAN_MODE=normal
CURSOR_AUTOSCALE_MIN_IDLE=1
CURSOR_AUTOSCALE_SCALE_STEP=2
CURSOR_AUTOSCALE_MAX_LOCAL_WORKERS=15
CURSOR_METRICS_NAMESPACE=Cursor/SelfHostedWorkers
```

Install the GitHub credential helper:

```bash
sudo install -m 755 bin/git-credential-github-secretsmanager /usr/local/bin/git-credential-github-secretsmanager
sudo -u ubuntu git config --global credential.helper /usr/local/bin/git-credential-github-secretsmanager
sudo rm -f /home/ubuntu/.git-credentials
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

If `CURSOR_REPO_ENV_FILES` is set, `cursor-worker-start` then writes repo-local env/config files from Secrets Manager into the worktree (see **Required AWS Secrets** above). This happens after cleanup and before the worker registers, so each new claimed session sees the hydrated files from the start.

Additional workers use git worktrees created from the base checkout. Those
worktrees start from `origin/<branch>` and may initially be detached at that
remote commit. Agent tasks that make changes should create or check out a
feature branch, commit, and push before finishing.

Follow-up turns sent before `CURSOR_WORKER_IDLE_RELEASE_TIMEOUT` expires can
reuse the still-claimed worker and its current working tree. After the timeout
expires, the worker is released and restarted; the next session starts from a
clean worktree reset to `origin/<branch>`. Users should commit and push any
changes they want to keep before the session times out. For follow-ups after a
timeout, instruct the agent to pull or check out the branch that contains the
prior work before continuing.

## Autoscaling

`cursor-workers-autoscale` scales up when idle capacity is too low and scales
down extra workers only after they have been idle long enough. Defaults are
configured in `/etc/cursor-workers/env`:

```text
CURSOR_AUTOSCALE_MIN_IDLE=1
CURSOR_AUTOSCALE_SCALE_STEP=2
CURSOR_AUTOSCALE_MAX_LOCAL_WORKERS=15
CURSOR_AUTOSCALE_BASE_WORKERS=5
CURSOR_AUTOSCALE_SCALE_DOWN_STEP=1
CURSOR_AUTOSCALE_SCALE_DOWN_IDLE_SECONDS=3600
CURSOR_AUTOSCALE_STATE_FILE=/var/lib/cursor-workers/autoscale-state.json
```

It reads `/etc/cursor-workers/workers.json` and each local `/readyz` endpoint.
If idle capacity is below `CURSOR_AUTOSCALE_MIN_IDLE`, it appends workers and
calls `cursor-workers-reconcile`. If extra workers above
`CURSOR_AUTOSCALE_BASE_WORKERS` have been idle for at least
`CURSOR_AUTOSCALE_SCALE_DOWN_IDLE_SECONDS`, it removes at most
`CURSOR_AUTOSCALE_SCALE_DOWN_STEP` worker per run.

Scale-down only removes workers that are currently connected, unclaimed, and
`status=ok`. It never removes workers at or below `CURSOR_AUTOSCALE_BASE_WORKERS`
and it keeps at least `CURSOR_AUTOSCALE_MIN_IDLE` idle worker available.
Idle age is tracked in `CURSOR_AUTOSCALE_STATE_FILE`; if a worker becomes
claimed or unready, its idle timer is cleared.

`cursor-workers-autoscale` and `cursor-workers-reconcile` both take local
`flock` locks, so a timer run and a manual reconcile do not edit
`workers.json` or create worktrees at the same time.

The default autoscaler uses local worker state so it stays correct when a Cursor
team has multiple self-hosted fleets. If a deployment has exactly one Cursor
team, one EC2 instance, and no other self-hosted workers, the simpler
team-summary approach in `examples/cursor-workers-autoscale-team-summary.example.sh`
can be used instead. That version reads `GET /v0/private-workers/summary` and
assumes the team-wide totals match the local EC2 fleet.

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

For one worker:

```bash
sudo journalctl -u cursor-worker-3.service -f
```

For journal metadata-level verbosity:

```bash
sudo journalctl -u cursor-worker-3.service -f -o verbose
```

`journalctl -o verbose` only changes journal output formatting. It does not
make the Cursor agent emit more logs.

If Cursor support asks for agent-level `--verbose` or `--debug`, run one idle
worker manually in the foreground instead of changing the shared scripts:

```bash
sudo systemctl stop cursor-worker-3.service

set -a
. /etc/cursor-workers/env
set +a

export CURSOR_API_KEY="$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$CURSOR_API_SECRET_ID" \
  --query SecretString \
  --output text)"

agent worker start --pool \
  --pool-name "$CURSOR_WORKER_POOL_NAME" \
  --worker-dir /opt/cursor-workers/worker-3 \
  --management-addr 127.0.0.1:8083 \
  --idle-release-timeout "$CURSOR_WORKER_IDLE_RELEASE_TIMEOUT" \
  --name ec2-worker-3 \
  --verbose
```

Use `--debug` instead of `--verbose` only when needed. Press `Ctrl+C` to stop
the foreground worker, then return it to systemd with `sudo systemctl start
cursor-worker-3.service`.

View autoscaler logs:

```bash
sudo journalctl -u cursor-workers-autoscale.service -n 100 --no-pager
```

View metrics publisher logs:

```bash
sudo journalctl -u cursor-workers-metrics.service -n 100 --no-pager
```

## Fleet API Visibility

The team summary endpoint is useful for team-wide capacity, but it is not scoped
to this EC2 instance or service account:

```bash
CURSOR_API_KEY="$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$CURSOR_API_SECRET_ID" \
  --query SecretString \
  --output text)"

curl -s -u "$CURSOR_API_KEY:" \
  "https://api.cursor.com/v0/private-workers/summary" | jq
```

`teamSummary.totalConnected` and `teamSummary.inUse` count all self-hosted
workers in the Cursor team. Do not use this endpoint alone to decide how many
workers this EC2 instance should add.

For worker-level visibility, list workers and filter by repo, worker name, and
service account:

```bash
curl -s -u "$CURSOR_API_KEY:" \
  "https://api.cursor.com/v0/private-workers?status=all&limit=100" \
  | jq '.workers[]
      | select(.repoOwner=="YOUR_ORG" and .repoName=="YOUR_REPO")
      | select(.name | startswith("ec2-worker-"))
      | {name, isInUse, activeBcId, serviceAccountId}'
```

Current public API responses expose worker names, repo metadata, service account
IDs, and usage state. They do not expose custom labels from `--labels-file`, so
labels should not be used as the source of truth for API-side scoping.

This repo's autoscaler intentionally uses local truth instead:

```text
/etc/cursor-workers/workers.json
127.0.0.1:<managementPort>/readyz
systemctl is-active cursor-worker-<id>.service
```

That keeps scaling scoped to this EC2 fleet even when the Cursor team has other
self-hosted workers connected.

If this EC2 instance is the only self-hosted worker fleet in the Cursor team,
the simpler team-summary path is acceptable:

```bash
CURSOR_API_KEY="$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$CURSOR_API_SECRET_ID" \
  --query SecretString \
  --output text)"

curl -s -u "$CURSOR_API_KEY:" \
  "https://api.cursor.com/v0/private-workers/summary" \
  | jq '{total: .teamSummary.totalConnected, inUse: .teamSummary.inUse, idle: (.teamSummary.totalConnected - .teamSummary.inUse)}'
```

In that single-fleet case, `examples/cursor-workers-autoscale-team-summary.example.sh`
shows how to scale this EC2 based on team-wide idle capacity. Do not use that
example once the Cursor team has more than one worker host, repo fleet, service
account fleet, or external self-hosted worker pool.

## Notes

- Do not commit real API keys, GitHub tokens, `.pem` files, or `/etc/cursor-worker/api-key`.
- The Cursor service account key is used by worker processes. End users do not need this key.
- Pool names and labels are routing/capacity metadata, not a security boundary.
- Use separate Cursor teams, GitHub integrations, service accounts, and fleets for hard isolation between groups or customers.
- The public private-workers API exposes worker names, repo metadata, service account IDs, and usage state. It should not be treated as an authoritative source for custom worker labels.
- The local autoscaler removes only extra idle workers above the configured base floor after the idle-age threshold. It never stops claimed workers.
