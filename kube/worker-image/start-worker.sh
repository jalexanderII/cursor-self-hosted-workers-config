#!/usr/bin/env bash
set -euo pipefail

# This script runs as PID 1 inside each worker pod.
#
# Kubernetes/EKS worker strategy:
# - No git worktrees are needed. Every pod has its own filesystem, so every
#   worker gets an isolated fresh clone.
# - The Cursor controller mounts a short-lived auth token at
#   /var/run/cursor/token. The agent CLI re-reads that file when reconnecting,
#   so the controller can rotate tokens without restarting the pod.
# - Repo-local secret files are mounted from Kubernetes Secrets and copied into
#   the fresh clone before the worker registers.
# - The worker name and worker directory should use the pod name. If every pod
#   uses /workspace/repo, the Cursor UI displays every worker as "repo".

: "${GITHUB_PAT:?missing GITHUB_PAT}"
: "${REPO_SLUG:?missing REPO_SLUG, for example owner/repo}"
: "${BRANCH:=main}"
: "${CURSOR_WORKER_POOL_NAME:=default}"
: "${IDLE_RELEASE_TIMEOUT:=900}"
: "${WORKER_DIR:=/workspace/${HOSTNAME:-repo}}"
: "${REPO_ENV_DIR:=/repo-env}"
: "${REPO_ENV_MAPPINGS:=}"
: "${CURSOR_WORKER_LABELS:=}"

# This script deletes and recreates WORKER_DIR every pod start. Keep it scoped
# under /workspace so a bad env var cannot remove arbitrary filesystem paths.
case "$WORKER_DIR" in
  /workspace/*) ;;
  *)
    echo "WORKER_DIR must be under /workspace, got: ${WORKER_DIR}" >&2
    exit 1
    ;;
esac

rm -rf "$WORKER_DIR"

# Use GIT_ASKPASS so the PAT is not written into the git remote URL or a file.
askpass="$(mktemp)"
trap 'rm -f "$askpass"' EXIT
cat > "$askpass" <<'ASKPASS'
#!/usr/bin/env sh
case "$1" in
  *Username*) echo "x-access-token" ;;
  *Password*) printf '%s\n' "$GITHUB_PAT" ;;
  *) echo "" ;;
esac
ASKPASS
chmod 700 "$askpass"

GIT_ASKPASS="$askpass" git clone --branch "$BRANCH" "https://github.com/${REPO_SLUG}.git" "$WORKER_DIR"
rm -f "$askpass"
trap - EXIT

# Optional mapping format:
#   mounted-secret-file-name:repo/relative/target/path
#
# Example:
#   app.env:.env,api.env:services/api/.env
#
# Kubernetes Secret keys become files under REPO_ENV_DIR. This copy step places
# them at the repo paths the tools expect. The mounted secret remains read-only;
# the copied file gets 0600 permissions inside the worker clone.
if [ -n "$REPO_ENV_MAPPINGS" ]; then
  IFS=',' read -r -a mappings <<< "$REPO_ENV_MAPPINGS"
  for mapping in "${mappings[@]}"; do
    source_name="${mapping%%:*}"
    target_rel="${mapping#*:}"

    if [ -z "$source_name" ] || [ -z "$target_rel" ] || [ "$source_name" = "$target_rel" ]; then
      echo "Invalid REPO_ENV_MAPPINGS entry: ${mapping}" >&2
      exit 1
    fi
    if [[ "$target_rel" == /* ]] || [[ "$target_rel" == *".."* ]] || [[ "$target_rel" == */ ]]; then
      echo "Invalid repo env target path: ${target_rel}" >&2
      exit 1
    fi
    if [ ! -f "${REPO_ENV_DIR}/${source_name}" ]; then
      echo "Missing mounted repo env secret file: ${REPO_ENV_DIR}/${source_name}" >&2
      exit 1
    fi

    mkdir -p "$(dirname "${WORKER_DIR}/${target_rel}")"
    cp "${REPO_ENV_DIR}/${source_name}" "${WORKER_DIR}/${target_rel}"
    chmod 600 "${WORKER_DIR}/${target_rel}"
  done
fi

cmd=(
  agent worker
  --pool
  --pool-name "$CURSOR_WORKER_POOL_NAME"
  --idle-release-timeout "$IDLE_RELEASE_TIMEOUT"
  --worker-dir "$WORKER_DIR"
  --auth-token-file /var/run/cursor/token
  --management-addr 0.0.0.0:8080
)

# Cursor labels are different from Kubernetes pod labels. Use these for routing
# or visibility in Cursor. Do not set reserved labels manually: repo and pool.
if [ -n "$CURSOR_WORKER_LABELS" ]; then
  IFS=',' read -r -a labels <<< "$CURSOR_WORKER_LABELS"
  for label in "${labels[@]}"; do
    if [ -n "$label" ]; then
      cmd+=(--label "$label")
    fi
  done
fi

exec "${cmd[@]}" start
