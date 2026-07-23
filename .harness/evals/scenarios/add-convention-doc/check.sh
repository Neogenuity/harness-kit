#!/usr/bin/env bash
# Grader: run in the post-agent workspace (cwd). Exit 0 = pass.
set -uo pipefail
doc="docs/standards/error-handling.md"
[ -f "$doc" ] || { echo "missing $doc"; exit 1; }
grep -qE '^# ' "$doc" || { echo "$doc has no top-level '# ' heading"; exit 1; }
[ "$(wc -w < "$doc")" -ge 20 ] || { echo "$doc is too short to be real guidance"; exit 1; }
grep -qF '(docs/standards/error-handling.md)' AGENTS.md \
    || { echo "AGENTS.md does not link docs/standards/error-handling.md"; exit 1; }
env HARNESS_NESTED_FIXTURE=1 bash scripts/harness/check-harness || { echo "check-harness.sh failed"; exit 1; }
echo "ok"; exit 0
