#!/usr/bin/env bash
# Reference solution: template-first, with mirrors (grader-validity proof).
# bash/sed/jq only — the kit's dependency floor (no python3).
set -euo pipefail
TPL="plugins/harness-kit/skills/harness-kit/templates"

# 1. Template SECRET_PATTERNS gains *.key (the gating change).
sed -i.bak 's/^SECRET_PATTERNS="\(.*\)"$/SECRET_PATTERNS="\1 *.key"/' "$TPL/scripts/harness.conf"
rm -f "$TPL/scripts/harness.conf.bak"

# 2. Mirror: template guard-secrets regression test gains a case marker.
printf '\n# *.key covered as a secret pattern (audit reference)\n# case: expect_deny "app/server.key"\n' \
    >> "$TPL/scripts/hooks/test-guard-secrets.sh"

# 3. Mirror: provider deny-list templates (jq, not python3).
cs="$TPL/providers/claude/settings.json"
jq '.permissions = (.permissions // {})
    | .permissions.deny = ((.permissions.deny // [])
        + (["Read(./*.key)", "Read(**/*.key)"] - (.permissions.deny // [])))' \
    "$cs" > "$cs.tmp" && mv "$cs.tmp" "$cs"

oc="$TPL/providers/opencode/opencode.json"
jq '.permission = (.permission // {})
    | .permission.read = ((.permission.read // {}) + {"**/*.key": "deny"})' \
    "$oc" > "$oc.tmp" && mv "$oc.tmp" "$oc"

echo "reference applied"
