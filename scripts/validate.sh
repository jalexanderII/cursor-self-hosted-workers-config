#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

required=(terraform python3 shellcheck)
for tool in "${required[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "required validation tool is missing: ${tool}" >&2
    exit 1
  fi
done

terraform fmt -check -recursive terraform

for directory in \
  terraform/examples/ec2-asg \
  terraform/examples/eks-new-cluster \
  terraform/examples/eks-existing-cluster; do
  terraform -chdir="$directory" init -backend=false -input=false >/dev/null
  terraform -chdir="$directory" validate
done

shellcheck ec2/bin/* kube/worker-image/*.sh scripts/*.sh

for script in ec2/bin/* kube/worker-image/*.sh scripts/*.sh; do
  bash -n "$script"
done

python3 -m unittest discover -s tests -p 'test_*.py'

echo "Repository validation passed."
