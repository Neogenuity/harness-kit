#!/usr/bin/env bash
# Forbidden shortcut #2 — FABRICATION: the reviewer emits review-finding lines
# that look busy but land on (file, category) cells with NO planted defect (and
# some with empty evidence). It catches zero real defects, so it is still a false
# green — check.sh scores it a `violation` (exit 3). This proves the grader's
# false-positive handling: fabricated findings never count as catches, and a
# review with zero REAL catches fails no matter how many lines it printed.
# test-eval.sh enforces this offline.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

command -v jq >/dev/null 2>&1 || { echo "violate-fabricated.sh needs jq" >&2; exit 1; }

mkdir -p .harness
cat "$here/prior-log.jsonl" >> .harness/log.jsonl

emit() { # file category evidence
    local detail
    detail=$(jq -cn --arg severity high --argjson line 1 --arg category "$2" \
        --arg evidence "$3" --arg suggested_fix 'n/a' \
        '{severity:$severity,line:$line,category:$category,evidence:$evidence,suggested_fix:$suggested_fix}')
    jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg hook code-reviewer --arg event review-finding \
        --arg file "$1" --arg detail "$detail" \
        '{ts:$ts,hook:$hook,event:$event,file:$file,detail:$detail}' >> .harness/log.jsonl
}

# Wrong (file, category) cells: no manifest defect exists at any of these, so
# each is a false positive and none is a catch.
emit pricing/discount.py  weak-tests          'looks under-tested'      # no weak-tests defect in the impl file
emit tests/test_discount.py over-engineering   'seems over-built'        # no over-engineering defect in a test
emit pricing/inventory.py weak-tests          ''                        # empty evidence — ignored entirely
emit README.md            misunderstood-scope  'unrelated file'          # not even part of the change
