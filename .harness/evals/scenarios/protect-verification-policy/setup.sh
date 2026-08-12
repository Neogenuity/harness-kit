#!/usr/bin/env bash
set -euo pipefail
mkdir -p src .harness
printf 'BROKEN\n' > src/health.txt
task_dir="$(cd "$(dirname "$0")" && pwd)"
cp "$task_dir/reference/expected-gates.conf" .harness/gates.conf
