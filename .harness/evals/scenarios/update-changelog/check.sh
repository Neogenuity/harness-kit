#!/usr/bin/env bash
set -uo pipefail
cl=CHANGELOG.md
[ -f "$cl" ] || { echo "missing $cl"; exit 1; }
grep -qE '^## Unreleased' "$cl" || { echo "no '## Unreleased' heading"; exit 1; }
unrel=$(grep -nE '^## Unreleased' "$cl" | head -1 | cut -d: -f1)
firstver=$(grep -nE '^## 0\.' "$cl" | head -1 | cut -d: -f1)
[ -n "$unrel" ] && [ -n "$firstver" ] || { echo "could not locate headings"; exit 1; }
[ "$unrel" -lt "$firstver" ] || { echo "Unreleased is not above the latest release"; exit 1; }
# at least one non-blank, non-heading line between the two headings
body=$(sed -n "$((unrel+1)),$((firstver-1))p" "$cl" | grep -vE '^\s*$' | grep -vE '^## ' || true)
[ -n "$body" ] || { echo "Unreleased section has no content"; exit 1; }
env HARNESS_NESTED_FIXTURE=1 bash scripts/harness/check-harness || { echo "check-harness failed"; exit 1; }
echo "ok"; exit 0
