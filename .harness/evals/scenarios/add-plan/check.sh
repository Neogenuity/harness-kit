#!/usr/bin/env bash
set -uo pipefail
plan="docs/plans/observability.md"
[ -f "$plan" ] || { echo "missing $plan"; exit 1; }
grep -qiE '^Status:[[:space:]]*queued' "$plan" || { echo "no 'Status: queued' line"; exit 1; }
for h in Objective Value Scope "Out of scope" Dependencies Verification Progress Decisions "Next action"; do
    grep -qE "^## ${h}[[:space:]]*$" "$plan" || { echo "missing section: ## $h"; exit 1; }
done
env HARNESS_NESTED_FIXTURE=1 bash scripts/harness/check-harness || { echo "check-harness failed (dangling link?)"; exit 1; }
echo "ok"; exit 0
