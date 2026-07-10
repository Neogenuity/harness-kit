#!/usr/bin/env bash
# Regression tests for lib.sh:hook_affected_files / hook_command_string —
# the payload-normalization layer every guard rides on. Runnable standalone
# and in CI.
#
# The Codex cases are built from the documented hook schema
# (https://learn.chatgpt.com/docs/hooks): payloads carry turn_id/tool_name/
# tool_use_id/tool_input, file edits arrive as an apply_patch invocation in
# tool_input.command, and there is NO file_path field. The docs show no
# verbatim payload example, so if a captured real payload ever differs, fix
# the builders below — the guard tests reuse the same shapes.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

LIB="$(cd "$(dirname "$0")" && pwd)/lib.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export HARNESS_LOG=0

# Fixture hook: print exactly what hook_affected_files extracts.
cp "$LIB" "$WORK/lib.sh"
cat > "$WORK/fixture-hook.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh"
hook_read_input
hook_affected_files
EOF
chmod +x "$WORK/fixture-hook.sh"
HOOK="$WORK/fixture-hook.sh"

fails=0

# run <description> <stdin-payload> <expected-output (newline-separated)>
run() {
    local desc="$1" payload="$2" want="$3" out rc
    out=$(printf '%s' "$payload" | "$HOOK" 2>/dev/null)
    rc=$?
    if [ "$rc" != "0" ]; then
        echo "FAIL: $desc — expected exit 0, got $rc"
        fails=$((fails + 1)); return
    fi
    if [ "$out" != "$want" ]; then
        echo "FAIL: $desc — expected [$want], got [$out]"
        fails=$((fails + 1)); return
    fi
    echo "ok:   $desc"
}

# Codex payload builders — the documented envelope, one place to fix if a
# captured real payload differs.
codex_cmd() { # <tool_name> <command-string> -> payload JSON
    jq -cn --arg t "$1" --arg c "$2" \
        '{turn_id: "t1", tool_name: $t, tool_use_id: "c1", tool_input: {command: $c}}'
}
patch_cmd() { # <patch-body> -> quoted-heredoc apply_patch shell command
    printf "apply_patch <<'EOF'\n*** Begin Patch\n%s\n*** End Patch\nEOF" "$1"
}

# --- direct file-path layouts (Cursor / Claude Code) ---
run "Cursor top-level file_path"    '{"file_path":"a.py"}'                    "a.py"
run "Claude nested file_path"       '{"tool_input":{"file_path":"a.py"}}'     "a.py"
run "Claude Grep path"              '{"tool_input":{"path":"src"}}'           "src"

# --- Codex apply_patch envelope, all three shell-quoting forms ---
run "Codex patch: quoted heredoc" \
    "$(codex_cmd apply_patch "$(patch_cmd '*** Update File: src/app.py
@@
+x')")" \
    "src/app.py"
run "Codex patch: unquoted heredoc" \
    "$(codex_cmd apply_patch "$(printf 'apply_patch <<EOF\n*** Begin Patch\n*** Update File: src/app.py\n*** End Patch\nEOF')")" \
    "src/app.py"
run "Codex patch: direct-argument form" \
    "$(codex_cmd apply_patch "$(printf "apply_patch '*** Begin Patch\n*** Update File: a.py\n@@\n+x\n*** End Patch'")")" \
    "a.py"

# --- multi-file patch: every header, in order; rename yields both paths ---
run "Codex patch: multi-file + rename" \
    "$(codex_cmd apply_patch "$(patch_cmd '*** Update File: a.py
@@
+x
*** Add File: b.py
+y
*** Delete File: c.py
*** Update File: old.py
*** Move to: new.py')")" \
    "a.py
b.py
c.py
old.py
new.py"
run "Codex patch: duplicate paths deduped" \
    "$(codex_cmd apply_patch "$(patch_cmd '*** Update File: a.py
@@
+x
*** Update File: a.py
@@
+y')")" \
    "a.py"
run "Codex patch: path with spaces intact" \
    "$(codex_cmd apply_patch "$(patch_cmd '*** Update File: docs/my file.md
@@
+x')")" \
    "docs/my file.md"

# --- argv-array command form ---
run "Codex argv-array command" \
    "$(jq -cn --arg c "$(patch_cmd '*** Update File: a.py
@@
+x')" '{tool_input: {command: ["bash", "-lc", $c]}}')" \
    "a.py"

# --- fail-open: no paths extracted ---
run "plain shell command yields nothing" "$(codex_cmd shell 'ls -la src/')" ""
run "empty payload yields nothing"       '{}'                                ""
run "empty stdin yields nothing"         ''                                  ""

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails affected-files case(s)"
    exit 1
fi
echo "PASSED: all affected-files cases"
