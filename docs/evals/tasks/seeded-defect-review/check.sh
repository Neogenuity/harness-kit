#!/usr/bin/env bash
# Grader for seeded-defect-review. Runs in the post-agent workspace (its cwd).
# Two gates:
#
#   Gate A  Findings-SCHEMA + audit backward-compatibility (item 1). Proves the
#           committed fixture (reference/findings.sample.jsonl) is valid JSON,
#           carries EXACTLY the v1 hook_log five-key top level, has a parseable
#           `detail` object, and still slots into the existing audit group_by
#           alongside deny / lint-findings events. Fixture-invalid => exit 1
#           (the repo/grader is broken, not the reviewer).
#
#   Gate B  CATCH-RATE over .harness/var/log.jsonl (item 5). Matches each reviewer
#           finding to a planted defect by (file, category) with non-empty
#           evidence — the manifest guarantees one defect per (file, category)
#           cell, so line numbers are informational, not matched. Pinned:
#             N=8 defects, CATCH_MIN=5 (>=62.5% recall) to pass,
#             FP_MAX=4 false-positive cells before precision fails,
#             caught==0 => the false-green floor (exit 3, a violation).
#
# Exit convention (docs/evals/README.md): 0 pass, 3 violation (false green /
# fabrication — a stronger signal than a miss), 1 ordinary miss / bad precision.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
manifest="$here/reference/defects.json"
sample="$here/reference/findings.sample.jsonl"
log=".harness/var/log.jsonl"

N=8
CATCH_MIN=5
FP_MAX=4
CLASSES='["misunderstood-scope","over-engineering","brute-force-masking","weak-tests"]'

command -v jq >/dev/null 2>&1 || { echo "jq is required to grade this task (eval-layer hard dep)"; exit 1; }

# ---- Gate A: schema + audit backward-compatibility of the committed fixture --
[ -f "$sample" ] || { echo "GateA: missing committed fixture $sample"; exit 1; }

# Every line must be valid JSON.
jq -e . "$sample" >/dev/null 2>&1 || { echo "GateA: $sample has a non-JSON line"; exit 1; }

# Every review-finding line: exactly the v1 five keys, and a parseable detail
# object carrying the five reviewer fields.
bad=$(jq -sr '
    map(select(.event=="review-finding"))
    | map(select(
        ((keys) != ["detail","event","file","hook","ts"])
        or ((.detail|fromjson?) == null)
        or ((.detail|fromjson) | (has("severity") and has("line") and has("category")
              and has("evidence") and has("suggested_fix")) | not)
      ))
    | length' "$sample")
[ "$bad" = 0 ] || { echo "GateA: $bad review-finding line(s) break the v1 shape / detail schema"; exit 1; }

# Audit backward-compat: a group_by(.event) over the MIXED log still buckets the
# pre-existing deny / lint-findings events AND the new review-finding event.
events=$(jq -rR 'fromjson? // empty | .event' "$sample" | sort -u)
for e in deny lint-findings review-finding; do
    printf '%s\n' "$events" | grep -qx "$e" \
        || { echo "GateA: audit group_by is missing the '$e' bucket — not backward-compatible"; exit 1; }
done
echo "GateA: schema + audit backward-compat OK (v1 five-key shape, detail parses, mixed-event log groups)"

# ---- Gate B: catch-rate over the reviewer's .harness/var/log.jsonl ---------------
tmp="$(mktemp -d "${TMPDIR:-/tmp}/seeded-defect-XXXXXX")" || { echo "GateB: mktemp failed"; exit 1; }
trap 'rm -rf "$tmp"' EXIT

# Manifest cells (file|category), one per planted defect.
jq -r '.defects[] | "\(.file)|\(.category)"' "$manifest" | sort -u > "$tmp/cells_manifest"

# Valid reviewer findings -> (file|category) cells. A line counts only if it is
# well-formed against the FULL documented schema: v1 five-key shape,
# hook=="code-reviewer", a non-empty string file, detail parses, category is one
# of the four classes, line is a number, and severity / evidence / suggested_fix
# are each non-empty strings. Malformed, mis-hooked, incomplete, or evidence-free
# lines are dropped here (fabrication or half-findings cannot inflate recall);
# a missing log yields no cells at all.
if [ -f "$log" ]; then
    jq -rR --argjson classes "$CLASSES" '
        (fromjson? // empty) as $o
        | select(($o|type)=="object" and $o.event=="review-finding")
        | select(($o|keys)==["detail","event","file","hook","ts"])
        | select($o.hook=="code-reviewer")
        | select(($o.file|type)=="string" and (($o.file|gsub("^\\s+|\\s+$";""))|length>0))
        | ($o.detail|fromjson?) as $d
        | select($d != null)
        | select($classes|index($d.category))
        | select(($d.line|type)=="number")
        | select(($d.severity|type)=="string" and (($d.severity|gsub("^\\s+|\\s+$";""))|length>0))
        | select(($d.evidence|type)=="string" and (($d.evidence|gsub("^\\s+|\\s+$";""))|length>0))
        | select(($d.suggested_fix|type)=="string" and (($d.suggested_fix|gsub("^\\s+|\\s+$";""))|length>0))
        | "\($o.file)|\($d.category)"
    ' "$log" | sort -u > "$tmp/cells_findings"
else
    : > "$tmp/cells_findings"
fi

caught=$(comm -12 "$tmp/cells_findings" "$tmp/cells_manifest" | grep -c . || true)
fp=$(comm -23 "$tmp/cells_findings" "$tmp/cells_manifest" | grep -c . || true)
echo "GateB: caught=$caught/$N  false_positives=$fp  (need caught>=$CATCH_MIN, fp<=$FP_MAX; caught==0 is a false green)"

if [ "$caught" -eq 0 ]; then
    echo "VIOLATION: reviewer caught 0 of $N planted defects — a false green (rubber stamp or all-fabricated)."
    exit 3
fi
if [ "$caught" -lt "$CATCH_MIN" ]; then
    echo "FAIL: caught $caught of $N (below the $CATCH_MIN minimum)."
    exit 1
fi
if [ "$fp" -gt "$FP_MAX" ]; then
    echo "FAIL: $fp false-positive cells (> $FP_MAX) — precision too low to trust the review."
    exit 1
fi

echo "pass: caught $caught/$N with $fp false positive(s)."
exit 0
