#!/usr/bin/env bash
set -euo pipefail

# Example autoscaler for the simplest deployment shape:
#
#   one Cursor team
#   one self-hosted worker fleet
#   one EC2 instance managing all workers for the team
#
# In that shape, the team-wide Cursor fleet summary should match the local EC2
# worker totals closely enough to drive scale-up decisions. Do not use this
# version if the Cursor team has multiple EC2 hosts, multiple worker fleets, or
# other self-hosted workers registered by another service account. In those
# cases, use bin/cursor-workers-autoscale, which scopes decisions to this
# instance's manifest and localhost /readyz endpoints.
set -a
. /etc/cursor-workers/env
set +a

MANIFEST="${CURSOR_WORKERS_MANIFEST:-/etc/cursor-workers/workers.json}"
MIN_IDLE="${CURSOR_AUTOSCALE_MIN_IDLE:-1}"
SCALE_STEP="${CURSOR_AUTOSCALE_SCALE_STEP:-2}"
MAX_LOCAL_WORKERS="${CURSOR_AUTOSCALE_MAX_LOCAL_WORKERS:-15}"

CURSOR_API_KEY="$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$CURSOR_API_SECRET_ID" \
  --query SecretString \
  --output text)"

summary="$(curl -s -u "$CURSOR_API_KEY:" \
  "https://api.cursor.com/v0/private-workers/summary")"

team_total="$(echo "$summary" | jq -r '.teamSummary.totalConnected // 0')"
team_in_use="$(echo "$summary" | jq -r '.teamSummary.inUse // 0')"
team_idle=$((team_total - team_in_use))

local_current="$(jq '.workers | length' "$MANIFEST")"

echo "team workers: total=${team_total} inUse=${team_in_use} idle=${team_idle}"
echo "local manifest: current=${local_current} minIdle=${MIN_IDLE} max=${MAX_LOCAL_WORKERS}"

if [ "$team_idle" -ge "$MIN_IDLE" ]; then
  echo "enough team idle workers; no scale-up needed"
  exit 0
fi

if [ "$local_current" -ge "$MAX_LOCAL_WORKERS" ]; then
  echo "max local workers reached; no scale-up"
  exit 0
fi

to_add="$SCALE_STEP"
if [ $((local_current + to_add)) -gt "$MAX_LOCAL_WORKERS" ]; then
  to_add=$((MAX_LOCAL_WORKERS - local_current))
fi

echo "scaling up this EC2 by ${to_add} worker(s)"

python3 - "$MANIFEST" "$to_add" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
to_add = int(sys.argv[2])

data = json.loads(path.read_text())
workers = data["workers"]

existing_ids = {int(w["id"]) for w in workers}
max_id = max(existing_ids) if existing_ids else 0
used_ports = {int(w["managementPort"]) for w in workers}

for _ in range(to_add):
    n = max_id + 1
    while n in existing_ids:
        n += 1

    port = 8080 + n
    while port in used_ports:
        port += 1

    workers.append({
        "id": str(n),
        "name": f"ec2-worker-{n}",
        "workerDir": f"/opt/cursor-workers/worker-{n}",
        "managementPort": port,
        "worktree": True
    })

    existing_ids.add(n)
    used_ports.add(port)
    max_id = n

path.write_text(json.dumps(data, indent=2) + "\n")
PY

/usr/local/bin/cursor-workers-reconcile
