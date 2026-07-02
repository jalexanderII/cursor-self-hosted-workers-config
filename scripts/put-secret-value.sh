#!/usr/bin/env bash
set -euo pipefail
umask 077

if [ "$#" -ne 1 ]; then
  echo "usage: $0 SECRET_ID" >&2
  echo "Reads the secret value from stdin." >&2
  exit 2
fi

secret_id="$1"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat >"$tmp"

if [ ! -s "$tmp" ]; then
  echo "refusing to write an empty secret value" >&2
  exit 1
fi

profile_args=()
if [ -n "${AWS_PROFILE:-}" ]; then
  profile_args=(--profile "$AWS_PROFILE")
fi

aws secretsmanager put-secret-value \
  "${profile_args[@]}" \
  --region "${AWS_REGION:?AWS_REGION must be set}" \
  --secret-id "$secret_id" \
  --secret-string "file://${tmp}" \
  >/dev/null

echo "Updated Secrets Manager secret ${secret_id}."
