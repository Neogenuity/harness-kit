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
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-guard-config.XXXXXX") || exit 1
# macOS TMPDIR normally ends in `/`, so the template above can yield a lexical
# `//` segment. Normalize it once: guard-config computes its repo root through
# `cd && pwd`, and absolute-path fixtures must use that same spelling.
WORK="$(cd "$WORK" && pwd)"
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
run 2 "dev-instance.sh edit denied"      "$(payload "$WORK/scripts/dev-instance.sh")"
run 2 "project dev.sh edit denied"       "$(payload "$WORK/scripts/dev.sh")"
run 2 "eval runner edit denied"          "$(payload "$WORK/scripts/eval.sh")"
run 2 "eval-lib edit denied"             "$(payload "$WORK/scripts/eval-lib.sh")"
run 2 "manifest edit denied"             "$(payload "$WORK/scripts/.harness-manifest")"
run 2 "regression test edit denied"      "$(payload "$WORK/scripts/test-check-harness.sh")"
run 2 "hook wiring edit denied"          "$(payload "$WORK/.claude/settings.json")"
run 2 "opencode.json (root) edit denied" "$(payload "$WORK/opencode.json")"
run 0 "opencode.json template editable (nested copy, not the root install)" "$(payload "$WORK/plugins/harness-kit/skills/harness-kit/templates/providers/opencode/opencode.json")"
run 2 "opencode.json root denied via dot-slash" "$(payload "$WORK/./opencode.json")"
run 2 "CI workflow edit denied"          "$(payload "$WORK/.github/workflows/ci.yml")"
run 2 "relative path denied"             "$(payload "scripts/hooks/guard-secrets.sh")"
run 2 "Cursor layout denied"             "$(cursor_payload "$WORK/scripts/sync-agent-skills.sh")"

# --- deny: 2026-07-12 probe-confirmed gaps (harness.conf, local settings, MCP configs) ---
run 2 "harness.conf edit denied"          "$(payload "$WORK/scripts/harness.conf")"
run 2 "Claude local settings edit denied" "$(payload "$WORK/.claude/settings.local.json")"
run 2 ".mcp.json edit denied"             "$(payload "$WORK/.mcp.json")"
run 2 "Cursor mcp.json edit denied"       "$(payload "$WORK/.cursor/mcp.json")"
run 2 "Codex config.toml edit denied"     "$(payload "$WORK/.codex/config.toml")"

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
# 2026-07-12 probe-confirmed gaps, both envelope forms — harness.conf via
# Update (the realistic edit path) and settings.local.json via Add (the
# realistic new-file attack: it's absent until an agent writes one).
run 2 "Codex patch: harness.conf edit denied"       "$(codex_patch '*** Update File: scripts/harness.conf
@@
+x')"
run 2 "Codex bare patch: harness.conf edit denied"  "$(codex_patch_bare '*** Update File: scripts/harness.conf
@@
+x')"
run 2 "Codex patch: dev-instance edit denied"       "$(codex_patch '*** Update File: scripts/dev-instance.sh
@@
+x')"
run 2 "Codex bare patch: project dev.sh edit denied" "$(codex_patch_bare '*** Update File: scripts/dev.sh
@@
+x')"
run 2 "Codex patch: Cursor sandbox edit denied" "$(codex_patch '*** Update File: .cursor/sandbox.json
@@
+x')"
run 2 "Codex bare patch: devcontainer edit denied" "$(codex_patch_bare '*** Update File: .devcontainer/devcontainer.json
@@
+x')"
run 2 "Codex patch: local settings add denied"      "$(codex_patch '*** Add File: .claude/settings.local.json
+{"disableAllHooks": true}')"
run 2 "Codex bare patch: local settings add denied" "$(codex_patch_bare '*** Add File: .claude/settings.local.json
+{"disableAllHooks": true}')"
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
run 0 "Codex patch: escape hatch allows dev-instance edit" "$(codex_patch '*** Update File: scripts/dev-instance.sh
@@
+x')" "HARNESS_ALLOW_MECHANISM_EDITS=1"
run 0 "Codex bare patch: escape hatch allows project dev.sh edit" "$(codex_patch_bare '*** Update File: scripts/dev.sh
@@
+x')" "HARNESS_ALLOW_MECHANISM_EDITS=1"

# --- 2026-07-12 review: dot-segment normalization ---
# A crafted `/./` or `/../` must not slip a protected path past the literal
# globs (`scripts/./harness.conf` resolves to `scripts/harness.conf`). Purely
# lexical; NOT case-folding — a case variant on a case-insensitive FS stays a
# documented guardrail limitation caught by the CI manifest layer.
run 2 "dot-slash harness.conf denied"          "$(payload "$WORK/scripts/./harness.conf")"
run 2 "dot-dot harness.conf denied"            "$(payload "$WORK/scripts/../scripts/harness.conf")"
run 2 "dot-slash settings.local denied"        "$(payload "$WORK/.claude/./settings.local.json")"
run 2 "dot-slash hook script denied"           "$(payload "$WORK/scripts/hooks/./lib.sh")"
run 2 "Cursor dot-slash mcp.json denied"       "$(cursor_payload "$WORK/.cursor/./mcp.json")"
run 2 "Cursor dot-slash sandbox denied"        "$(cursor_payload "$WORK/.cursor/./sandbox.json")"
run 2 "dot-slash devcontainer denied"          "$(payload "$WORK/.devcontainer/./devcontainer.json")"
run 2 "Codex patch dot-slash mid-path denied"  "$(codex_patch '*** Update File: scripts/./harness.conf
@@
+x')"
run 2 "Codex patch dot-dot mid-path denied"    "$(codex_patch '*** Update File: scripts/../scripts/.harness-manifest
@@
+x')"
run 0 "dot-slash ordinary file still allowed"  "$(payload "$WORK/src/./app.js")"

# --- deny-hint: optional GUARD_DENY_HINT is appended to the deny message ------
# guard-config.sh reads it from harness.conf (empty by default). Assert the FULL
# deny contract holds with no hint, then that a set hint is appended — via env
# (the fake repo has no harness.conf, so the env value survives) and via a real
# harness.conf file (the production source).
_hintout() { { printf '%s' "$1" | env HARNESS_LOG=0 HARNESS_ALLOW_MECHANISM_EDITS=0 ${2:-_=_} "$HOOK" >/dev/null; } 2>&1; }
out=$(_hintout "$(payload "$WORK/scripts/harness.conf")")
if printf '%s' "$out" | grep -q 'guard-config.sh' && printf '%s' "$out" | grep -q 'HARNESS_ALLOW_MECHANISM_EDITS=1'; then
    echo "ok:   empty hint — full deny contract intact (guard named + escape hatch)"
else
    echo "FAIL: empty-hint deny contract"; fails=$((fails+1))
fi
out=$(_hintout "$(payload "$WORK/scripts/harness.conf")" 'GUARD_DENY_HINT=EDIT-THE-TEMPLATE')
if printf '%s' "$out" | grep -q 'EDIT-THE-TEMPLATE'; then
    echo "ok:   env-provided hint is appended to the deny message"
else
    echo "FAIL: env hint not appended"; fails=$((fails+1))
fi
printf 'GUARD_DENY_HINT="hint-from-conf-file"\n' > "$WORK/scripts/harness.conf"
out=$(_hintout "$(payload "$WORK/scripts/hooks/lib.sh")")
if printf '%s' "$out" | grep -q 'hint-from-conf-file'; then
    echo "ok:   hint sourced from harness.conf is appended to the deny message"
else
    echo "FAIL: harness.conf hint not applied"; fails=$((fails+1))
fi
rm -f "$WORK/scripts/harness.conf"

# --- allow: ordinary files, escape hatch, fail-open ---
run 0 "ordinary source file allowed"     "$(payload "$WORK/src/app.php")"
run 0 "sibling name not protected"       "$(payload "$WORK/src/check-harness.sh.md")"
run 0 "escape hatch allows mechanism edit" "$(payload "$WORK/scripts/hooks/lib.sh")" "HARNESS_ALLOW_MECHANISM_EDITS=1"
run 0 "escape hatch allows harness.conf tailoring" "$(payload "$WORK/scripts/harness.conf")" "HARNESS_ALLOW_MECHANISM_EDITS=1"
run 0 "escape hatch allows direct dev-instance edit" "$(payload "$WORK/scripts/dev-instance.sh")" "HARNESS_ALLOW_MECHANISM_EDITS=1"
run 0 "escape hatch allows direct project dev.sh edit" "$(payload "$WORK/scripts/dev.sh")" "HARNESS_ALLOW_MECHANISM_EDITS=1"
run 0 "bare command payload fails open"  "$(jq -cn '{tool_input: {command: "ls"}}')"
run 0 "empty payload fails open"         '{}'

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails guard-config case(s)"
    exit 1
fi
echo "PASSED: all guard-config cases"
