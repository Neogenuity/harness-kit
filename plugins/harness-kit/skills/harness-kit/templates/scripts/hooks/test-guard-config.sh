#!/usr/bin/env bash
# Regression tests for guard-config.sh. Runnable standalone and in CI.
# Each case feeds a hook payload on stdin and asserts the exit code:
#   0 = allowed, 2 = denied.
#
# The guard protects the harness mechanism from agent edits; if you tailor
# PROTECTED_PATHS, extend these cases so the boundary stays pinned.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Run from a fake repo root so ROOT resolution and rel-path stripping are
# exercised exactly as installed.
mkdir -p "$WORK/scripts/hooks" "$WORK/src"
cp "$HOOKS_DIR/lib.sh" "$WORK/scripts/hooks/lib.sh"
cp "$HOOKS_DIR/guard-config.sh" "$WORK/scripts/hooks/guard-config.sh"
HOOK="$WORK/scripts/hooks/guard-config.sh"

fails=0

payload() { printf '{"tool_input":{"file_path":"%s"}}' "$1"; }
cursor_payload() { printf '{"file_path":"%s"}' "$1"; }

# run <expected-exit> <description> <json-payload> [env]
run() {
    local expected="$1" desc="$2" payload="$3" actual
    printf '%s' "$payload" | env HARNESS_LOG=0 ${4:-HARNESS_ALLOW_MECHANISM_EDITS=0} "$HOOK" >/dev/null 2>&1
    actual=$?
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $desc — expected exit $expected, got $actual"
        fails=$((fails + 1))
    else
        echo "ok:   $desc"
    fi
}

# --- deny: mechanism files, absolute and relative, both layouts ---
run 2 "hook script edit denied"          "$(payload "$WORK/scripts/hooks/lib.sh")"
run 2 "check-harness.sh edit denied"     "$(payload "$WORK/scripts/check-harness.sh")"
run 2 "install-lib.sh edit denied"       "$(payload "$WORK/scripts/install-lib.sh")"
run 2 "eval runner edit denied"          "$(payload "$WORK/scripts/eval.sh")"
run 2 "eval-lib edit denied"             "$(payload "$WORK/scripts/eval-lib.sh")"
run 2 "manifest edit denied"             "$(payload "$WORK/scripts/.harness-manifest")"
run 2 "regression test edit denied"      "$(payload "$WORK/scripts/test-check-harness.sh")"
run 2 "hook wiring edit denied"          "$(payload "$WORK/.claude/settings.json")"
run 2 "opencode.json edit denied"        "$(payload "$WORK/opencode.json")"
run 2 "CI workflow edit denied"          "$(payload "$WORK/.github/workflows/ci.yml")"
run 2 "relative path denied"             "$(payload "scripts/hooks/guard-secrets.sh")"
run 2 "Cursor layout denied"             "$(cursor_payload "$WORK/scripts/sync-agent-skills.sh")"

# --- Codex layout: apply_patch envelopes (paths are repo-relative) ---
# Builders mirror test-affected-files.sh — one place per file to fix if a
# captured real payload differs.
codex_patch() {
    jq -cn --arg c "$(printf "apply_patch <<'EOF'\n*** Begin Patch\n%s\n*** End Patch\nEOF" "$1")" \
        '{turn_id: "t1", tool_name: "apply_patch", tool_use_id: "c1", tool_input: {command: $c}}'
}
# Real Codex form: the BARE envelope, no "apply_patch" wrapper literal in the
# command (tool_name carries the identity). A live capture showed this is the
# actual shape; the wrapper-only fixtures above let a gate keyed on the
# "apply_patch" substring slip a mechanism edit through undenied.
codex_patch_bare() {
    jq -cn --arg c "$(printf '*** Begin Patch\n%s\n*** End Patch' "$1")" \
        '{turn_id: "t1", tool_name: "apply_patch", tool_use_id: "c1", tool_input: {command: $c}}'
}

run 2 "Codex patch: hook edit denied"            "$(codex_patch '*** Update File: scripts/hooks/lib.sh
@@
+x')"
run 2 "Codex patch: added protected file denied" "$(codex_patch '*** Add File: scripts/hooks/evil.sh
+#!/usr/bin/env bash')"
run 2 "Codex patch: rename onto mechanism denied" "$(codex_patch '*** Update File: src/x.sh
*** Move to: scripts/check-harness.sh')"
run 2 "Codex patch: multi-file, manifest second" "$(codex_patch '*** Update File: src/app.php
@@
+x
*** Update File: scripts/.harness-manifest
@@
+y')"
run 2 "Codex patch: dot-slash prefixed path denied" "$(codex_patch '*** Update File: ./scripts/hooks/lib.sh
@@
+x')"
run 0 "Codex patch: ordinary file allowed"       "$(codex_patch '*** Update File: src/app.php
@@
+x')"
# Real Codex form (bare envelope, no "apply_patch" literal) — the security
# regression: this exact shape sailed through the guard before the lib.sh gate
# was taught to recognize the bare envelope.
run 2 "Codex bare patch: hook edit denied"       "$(codex_patch_bare '*** Update File: scripts/hooks/lib.sh
@@
+x')"
run 2 "Codex bare patch: manifest edit denied"   "$(codex_patch_bare '*** Update File: scripts/.harness-manifest
@@
+x')"
run 0 "Codex bare patch: ordinary file allowed"  "$(codex_patch_bare '*** Update File: src/app.php
@@
+x')"
# General shell commands are deliberately NOT scanned (read vs write is
# indistinguishable from command text); check-harness.sh's manifest
# verification is the enforcing layer for shell edits.
run 0 "Codex shell: sed on mechanism not scanned (documented limit)" "$(jq -cn '{tool_input: {command: "sed -i s/a/b/ scripts/hooks/lib.sh"}}')"
# A plain shell command that merely CONTAINS patch text (tool_name shell, no
# "apply_patch" literal — a heredoc writing a .patch file) is not a patch
# application and must not fail-close the guard (PR #6 review): the bare
# envelope is only parsed when tool_name is apply_patch.
run 0 "Codex shell: patch text in a heredoc not treated as a mechanism edit" "$(jq -cn --arg c "$(printf 'cat > demo.patch <<PATCH\n*** Begin Patch\n*** Update File: scripts/hooks/lib.sh\n@@\n+evil\n*** End Patch\nPATCH')" '{turn_id: "t1", tool_name: "shell", tool_use_id: "c1", tool_input: {command: $c}}')"
run 0 "Codex patch: escape hatch allows mechanism edit" "$(codex_patch '*** Update File: scripts/hooks/lib.sh
@@
+x')" "HARNESS_ALLOW_MECHANISM_EDITS=1"

# --- allow: ordinary files, escape hatch, fail-open ---
run 0 "ordinary source file allowed"     "$(payload "$WORK/src/app.php")"
run 0 "sibling name not protected"       "$(payload "$WORK/src/check-harness.sh.md")"
run 0 "escape hatch allows mechanism edit" "$(payload "$WORK/scripts/hooks/lib.sh")" "HARNESS_ALLOW_MECHANISM_EDITS=1"
run 0 "bare command payload fails open"  "$(jq -cn '{tool_input: {command: "ls"}}')"
run 0 "empty payload fails open"         '{}'

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails guard-config case(s)"
    exit 1
fi
echo "PASSED: all guard-config cases"
