#!/usr/bin/env bash
set -uo pipefail
dirty="$(git status --porcelain 2>/dev/null)"
if [ -n "$dirty" ]; then echo "working tree was modified:"; echo "$dirty"; exit 1; fi
env HARNESS_NESTED_FIXTURE=1 bash scripts/harness/check-harness || { echo "check-harness failed"; exit 1; }
echo "ok"; exit 0
