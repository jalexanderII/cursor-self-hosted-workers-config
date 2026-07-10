#!/usr/bin/env bash
# Print ASG membership and each instance's local /readyz via SSM.
set -euo pipefail

asg_name="${1:-}"
if [[ -z "$asg_name" ]]; then
  asg_name="$(terraform -chdir="${EC2_TF_DIR:-terraform/examples/ec2-asg}" output -raw autoscaling_group_name 2>/dev/null || true)"
fi
if [[ -z "$asg_name" ]]; then
  echo "usage: $0 [ASG_NAME]" >&2
  exit 2
fi

profile_args=()
if [[ -n "${AWS_PROFILE:-}" ]]; then
  profile_args=(--profile "$AWS_PROFILE")
fi
region="${AWS_REGION:?AWS_REGION must be set}"

aws autoscaling describe-auto-scaling-groups \
  "${profile_args[@]}" \
  --region "$region" \
  --auto-scaling-group-names "$asg_name" \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:Instances[*].[InstanceId,LifecycleState,HealthStatus,ProtectedFromScaleIn]}' \
  --output table

mapfile -t instance_ids < <(
  aws autoscaling describe-auto-scaling-groups \
    "${profile_args[@]}" \
    --region "$region" \
    --auto-scaling-group-names "$asg_name" \
    --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
    --output text | tr '\t' '\n' | sed '/^$/d'
)

if [[ "${#instance_ids[@]}" -eq 0 ]]; then
  echo "No InService instances."
  exit 0
fi

remote_script='systemctl is-active cursor-worker-1.service 2>/dev/null || true
if [[ -f /etc/cursor-workers/workers.json ]]; then
  for p in $(jq -r ".workers[].managementPort" /etc/cursor-workers/workers.json); do
    echo "PORT=$p"
    curl -sS -m 3 "http://127.0.0.1:${p}/readyz" || true
    echo
  done
fi
journalctl -u cursor-worker-1.service -n 15 --no-pager 2>/dev/null || true'

params_file="$(mktemp)"
trap 'rm -f "$params_file"' EXIT
python3 - "$remote_script" "$params_file" <<'PY'
import json, sys
script = sys.argv[1]
path = sys.argv[2]
open(path, "w").write(json.dumps({"commands": [f"bash -lc {json.dumps(script)}"]}))
PY

for instance_id in "${instance_ids[@]}"; do
  echo "=== $instance_id ==="
  ping="$(
    aws ssm describe-instance-information \
      "${profile_args[@]}" \
      --region "$region" \
      --filters "Key=InstanceIds,Values=$instance_id" \
      --query 'InstanceInformationList[0].PingStatus' \
      --output text 2>/dev/null || echo None
  )"
  echo "SSM=$ping"
  if [[ "$ping" != "Online" ]]; then
    continue
  fi

  cmd_id="$(
    aws ssm send-command \
      "${profile_args[@]}" \
      --region "$region" \
      --instance-ids "$instance_id" \
      --document-name AWS-RunShellScript \
      --parameters "file://${params_file}" \
      --query 'Command.CommandId' \
      --output text
  )"

  for _ in $(seq 1 20); do
    status="$(
      aws ssm get-command-invocation \
        "${profile_args[@]}" \
        --region "$region" \
        --command-id "$cmd_id" \
        --instance-id "$instance_id" \
        --query Status \
        --output text 2>/dev/null || echo Pending
    )"
    if [[ "$status" == "Success" || "$status" == "Failed" || "$status" == "Cancelled" || "$status" == "TimedOut" ]]; then
      break
    fi
    sleep 2
  done

  aws ssm get-command-invocation \
    "${profile_args[@]}" \
    --region "$region" \
    --command-id "$cmd_id" \
    --instance-id "$instance_id" \
    --query StandardOutputContent \
    --output text
done
