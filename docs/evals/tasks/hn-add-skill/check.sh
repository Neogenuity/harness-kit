#!/usr/bin/env bash
# Grader copied semantically from docs/evals/tasks/add-skill-sync/check.sh
# (temporary audit variant — do not edit the tracked original).
set -uo pipefail
skill="docs/skills/changelog/SKILL.md"
[ -f "$skill" ] || { echo "missing $skill"; exit 1; }
head -1 "$skill" | grep -qx -- '---' || { echo "$skill has no YAML frontmatter"; exit 1; }
grep -qE '^name:[[:space:]]*changelog' "$skill" || { echo "frontmatter missing 'name: changelog'"; exit 1; }
grep -qE '^description:' "$skill" || { echo "frontmatter missing 'description:'"; exit 1; }
grep -qF '(docs/skills/changelog/SKILL.md)' AGENTS.md || { echo "AGENTS.md does not link the skill"; exit 1; }
env HARNESS_NESTED_FIXTURE=1 bash scripts/check-harness.sh || { echo "check-harness.sh failed (stub drift?)"; exit 1; }
echo "ok"; exit 0
