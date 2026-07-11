#!/usr/bin/env bash
set -uo pipefail
env HARNESS_NESTED_FIXTURE=1 bash scripts/check-harness.sh || { echo "check-harness.sh still failing (dangling link)"; exit 1; }
echo "ok"; exit 0
