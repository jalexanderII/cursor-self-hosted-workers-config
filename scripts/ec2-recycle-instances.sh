#!/usr/bin/env bash
# Replace ASG instances after secrets are populated (or after launch-template changes).
# Scale-in protection blocks plain terminate; this detaches unprotected and lets the
# ASG launch replacements that pick up current secrets/user-data.
set -euo pipefail

asg_name="${1:-}"
if [[ -z "$asg_name" ]]; then
  asg_name="$(terraform -chdir="${EC2_TF_DIR:-terraform/examples/ec2-asg}" output -raw autoscaling_group_name 2>/dev/null || true)"
fi
if [[ -z "$asg_name" ]]; then
  echo "usage: $0 [ASG_NAME]" >&2
  echo "Or run from a configured tree so terraform output autoscaling_group_name works." >&2
  exit 2
fi

profile_args=()
if [[ -n "${AWS_PROFILE:-}" ]]; then
  profile_args=(--profile "$AWS_PROFILE")
fi
region="${AWS_REGION:?AWS_REGION must be set}"

mapfile -t instance_ids < <(
  aws autoscaling describe-auto-scaling-groups \
    "${profile_args[@]}" \
    --region "$region" \
    --auto-scaling-group-names "$asg_name" \
    --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
    --output text | tr '\t' '\n' | sed '/^$/d'
)

if [[ "${#instance_ids[@]}" -eq 0 ]]; then
  echo "No instances in $asg_name; ASG should launch to desired capacity on its own."
  exit 0
fi

echo "Recycling ${#instance_ids[@]} instance(s) in $asg_name: ${instance_ids[*]}"

aws autoscaling set-instance-protection \
  "${profile_args[@]}" \
  --region "$region" \
  --auto-scaling-group-name "$asg_name" \
  --instance-ids "${instance_ids[@]}" \
  --no-protected-from-scale-in

aws autoscaling detach-instances \
  "${profile_args[@]}" \
  --region "$region" \
  --auto-scaling-group-name "$asg_name" \
  --instance-ids "${instance_ids[@]}" \
  --no-should-decrement-desired-capacity

# Detached instances are no longer ASG-managed; terminate them explicitly.
aws ec2 terminate-instances \
  "${profile_args[@]}" \
  --region "$region" \
  --instance-ids "${instance_ids[@]}" \
  >/dev/null

echo "Detached and terminating old instances. New ones will launch with current secrets/user-data."
