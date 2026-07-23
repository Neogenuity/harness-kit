#!/usr/bin/env bash
set -uo pipefail
env HARNESS_NESTED_FIXTURE=1 bash scripts/harness/check-harness || { echo "check-harness still failing (dangling link)"; exit 1; }
echo "ok"; exit 0
