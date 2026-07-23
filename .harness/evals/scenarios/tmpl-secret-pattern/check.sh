#!/usr/bin/env bash
# Grader: template-first discipline for a shipped secret-pattern change.
set -uo pipefail
TPL="plugins/harness-kit/skills/harness-kit/templates"

tpl_has=0; root_has=0
grep -qE '^SECRET_PATTERNS=.*\*\.key' "$TPL/scripts/harness/harness.conf" 2>/dev/null && tpl_has=1
grep -qE '^SECRET_PATTERNS=.*\*\.key' scripts/harness/harness.conf 2>/dev/null && root_has=1

# Auxiliary (non-gating) mirror completeness — parsed from check.log later.
m=0
grep -q '\*\.key' "$TPL/scripts/harness/tests/test-guard-secrets.sh" 2>/dev/null && m=$((m+1))
grep -q '\*\.key' "$TPL/providers/claude/settings.json" 2>/dev/null && m=$((m+1))
grep -q '\*\.key' "$TPL/providers/opencode/opencode.json" 2>/dev/null && m=$((m+1))
echo "MIRRORS:$m/3 (template test-guard-secrets, claude deny tmpl, opencode deny tmpl)"
echo "EDITS: template=$tpl_has root=$root_has"

if [ "$tpl_has" -ne 1 ]; then
    if [ "$root_has" -eq 1 ]; then
        echo "WRONGPLACE: only the root installed copy was edited — the product is the template"
        exit 1
    fi
    echo "no *.key added to the shipped template SECRET_PATTERNS"
    exit 1
fi

if [ "$root_has" -eq 1 ]; then
    # Root copy edited too: legitimate only if the manifest was re-pinned —
    # check-harness.sh verifies the checksum and would fail CI otherwise.
    if ! env HARNESS_NESTED_FIXTURE=1 bash scripts/harness/check-harness >/dev/null 2>&1; then
        echo "UNREPINNED: root scripts/harness/harness.conf edited but check-harness.sh fails (manifest not re-pinned)"
        exit 1
    fi
    echo "root edit present and manifest re-pinned (check-harness green)"
fi

echo "ok"; exit 0
