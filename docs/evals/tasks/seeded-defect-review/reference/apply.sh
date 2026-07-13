#!/usr/bin/env bash
# Reference solution — the IDEAL reviewer: catches all 8 planted defects and
# emits one v1-compatible hook_log line per finding, generated from the manifest
# so it can never drift from defects.json. Applying this then running check.sh
# MUST score `pass` (test-eval.sh enforces this offline, no model).
#
# It seeds the two pre-existing v1 log lines first (prior-log.jsonl), so the
# graded .harness/log.jsonl is a MIX of deny / lint-findings / review-finding —
# proving the schema is backward-compatible with the existing audit log.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "apply.sh needs jq" >&2; exit 1; }

mkdir -p .harness
cat "$here/prior-log.jsonl" >> .harness/log.jsonl

# One finding per manifest defect: file + category (the matched keys) come
# straight from defects.json; evidence is the manifest note (non-empty), the fix
# is a short concrete sentence. detail is built with a nested jq so escaping is
# never hand-rolled — the exact pattern the persona documents.
jq -c '.defects[]' "$here/defects.json" | while IFS= read -r d; do
    file=$(printf '%s' "$d" | jq -r '.file')
    category=$(printf '%s' "$d" | jq -r '.category')
    line=$(printf '%s' "$d" | jq -r '.line')
    evidence=$(printf '%s' "$d" | jq -r '.note')
    detail=$(jq -cn --arg severity high --argjson line "$line" \
        --arg category "$category" --arg evidence "$evidence" \
        --arg suggested_fix "address the $category issue per SPEC.md" \
        '{severity:$severity,line:$line,category:$category,evidence:$evidence,suggested_fix:$suggested_fix}')
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg hook code-reviewer --arg event review-finding \
        --arg file "$file" --arg detail "$detail" \
        '{ts:$ts,hook:$hook,event:$event,file:$file,detail:$detail}' >> .harness/log.jsonl
done
