#!/usr/bin/env bash
set -uo pipefail
skill=".agents/skills/changelog/SKILL.md"
[ -f "$skill" ] || { echo "missing $skill"; exit 1; }
head -1 "$skill" | grep -qx -- '---' || { echo "$skill has no YAML frontmatter"; exit 1; }
grep -qE '^name:[[:space:]]*changelog' "$skill" || { echo "frontmatter missing 'name: changelog'"; exit 1; }
grep -qE '^description:' "$skill" || { echo "frontmatter missing 'description:'"; exit 1; }
grep -qF '(.agents/skills/changelog/SKILL.md)' AGENTS.md || { echo "AGENTS.md does not link the skill"; exit 1; }
env HARNESS_NESTED_FIXTURE=1 bash scripts/harness/check-harness || { echo "check-harness.sh failed (stub drift?)"; exit 1; }
echo "ok"; exit 0
