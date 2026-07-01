#!/usr/bin/env bash
set -euo pipefail
umask 077

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "usage: $0 NAMESPACE SECRET_NAME KEY [WORKER_DEPLOYMENT]" >&2
  echo "Reads the secret value from stdin." >&2
  exit 2
fi

namespace="$1"
secret_name="$2"
key="$3"
worker_deployment="${4:-}"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat >"$tmp"

if [ ! -s "$tmp" ]; then
  echo "refusing to create an empty Kubernetes Secret" >&2
  exit 1
fi

kubectl create namespace "$namespace" --dry-run=client -o yaml |
  kubectl apply -f -

kubectl create secret generic "$secret_name" \
  --from-file="${key}=${tmp}" \
  -n "$namespace" \
  --dry-run=client -o yaml |
  kubectl apply -f -

if [ -n "$worker_deployment" ]; then
  kubectl label secret "$secret_name" \
    -n "$namespace" \
    "workers.cursor.com/worker-deployment=${worker_deployment}" \
    --overwrite
fi

echo "Updated Kubernetes Secret ${namespace}/${secret_name}."
