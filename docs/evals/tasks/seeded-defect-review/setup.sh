#!/usr/bin/env bash
# Seed the workspace with the change under review: the SPEC plus the defective
# implementation and tests (8 planted defects, 2 per failure class). They land
# as an uncommitted working-tree addition — the "PR" the reviewer inspects.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

cp -R "$here/fixture/." .

# Make the additions show up in `git diff` (intent-to-add), so a reviewer that
# diffs against HEAD sees them as the change. Best-effort — never fail setup.
git add -N pricing tests SPEC.md 2>/dev/null || true
