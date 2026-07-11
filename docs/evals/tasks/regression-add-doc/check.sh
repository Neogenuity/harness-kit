#!/usr/bin/env bash
set -uo pipefail
doc="docs/notes/scratch.md"
[ -f "$doc" ] || { echo "missing $doc"; exit 1; }
[ "$(wc -w < "$doc")" -ge 8 ] || { echo "$doc has no real prose"; exit 1; }
env HARNESS_NESTED_FIXTURE=1 bash scripts/check-harness.sh || { echo "check-harness.sh failed"; exit 1; }
echo "ok"; exit 0
