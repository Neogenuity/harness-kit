#!/usr/bin/env bash
# Regression tests for guard-secrets.sh. Runnable standalone and in CI.
# Each case feeds a hook payload on stdin and asserts the exit code:
#   0 = allowed, 2 = denied.
#
# If you tailor SECRET_PATTERNS / SECRET_ALLOW_PATTERNS in harness.conf,
# extend these cases to match — the test pins the deny boundary, including
# the symlink and case-folding behavior that is easy to regress, plus the
# fact that harness.conf is the authoritative pattern source.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

HOOK="$(cd "$(dirname "$0")" && pwd)/guard-secrets.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Keep hook_log out of the repo during tests; explicit log cases opt back in.
export HARNESS_LOG=0

fails=0

# run <expected-exit> <description> <json-payload>
run() {
    local expected="$1" desc="$2" payload="$3" actual
    printf '%s' "$payload" | "$HOOK" >/dev/null 2>&1
    actual=$?
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $desc — expected exit $expected, got $actual"
        fails=$((fails + 1))
    else
        echo "ok:   $desc"
    fi
}

# Real files to resolve symlinks against.
printf 'SECRET=1\n'        > "$WORK/.env"
printf 'EXAMPLE=1\n'       > "$WORK/.env.example"
ln -s "$WORK/.env"         "$WORK/notes.md"          # innocuous name -> secret
ln -s "$WORK/.env"         "$WORK/.env.example.link" # allow-ish name -> secret
ln -s "$WORK/.env.example" "$WORK/safe.link"         # -> example (safe)

payload() { printf '{"tool_input":{"file_path":"%s"}}' "$1"; }
cursor_payload() { printf '{"file_path":"%s"}' "$1"; }
grep_payload() { printf '{"tool_input":{"path":"%s"}}' "$1"; }

# --- deny: secret files, any case, both harness layouts ---
run 2 ".env is denied"               "$(payload "$WORK/.env")"
run 2 ".ENV (upper) is denied"       "$(payload "$WORK/.ENV")"
run 2 ".env.production denied"       "$(payload "$WORK/.env.production")"
run 2 "auth.json denied"             "$(payload "$WORK/auth.json")"
run 2 "AUTH.JSON (upper) denied"     "$(payload "$WORK/AUTH.JSON")"
run 2 "credentials.json denied"      "$(payload "$WORK/credentials.json")"
run 2 "server.pem denied"            "$(payload "$WORK/server.pem")"
run 2 "id_rsa denied"                "$(payload "$WORK/id_rsa")"
run 2 "id_ed25519 denied"            "$(payload "$WORK/id_ed25519")"
run 2 "Cursor layout .env denied"    "$(cursor_payload "$WORK/.env")"
run 2 "Grep path at .env denied"     "$(grep_payload "$WORK/.env")"

# --- deny: symlink laundering ---
run 2 "symlink notes.md->.env denied"          "$(payload "$WORK/notes.md")"
run 2 "symlink .env.example.link->.env denied" "$(payload "$WORK/.env.example.link")"

# --- allow: safe files ---
run 0 ".env.example allowed"         "$(payload "$WORK/.env.example")"
run 0 ".env.sample allowed"          "$(payload "$WORK/.env.sample")"
run 0 ".env.testing allowed"         "$(payload "$WORK/.env.testing")"
run 0 ".env.mcp.example allowed"     "$(payload "$WORK/.env.mcp.example")"
run 0 "symlink safe.link->example allowed" "$(payload "$WORK/safe.link")"
run 0 "ordinary source file allowed" "$(payload "$WORK/config.php")"
run 0 "Grep on directory allowed"    "$(grep_payload "$WORK")"
run 0 "empty payload fails open"     '{}'

# --- Codex layout: shell commands (best-effort token scan) ---
# On Codex every file read is a shell command, so the token scan is the only
# live secret layer there. Builders mirror test-affected-files.sh — one
# place per file to fix if a captured real payload differs.
codex_shell() {
    jq -cn --arg c "$1" \
        '{turn_id: "t1", tool_name: "shell", tool_use_id: "c1", tool_input: {command: $c}}'
}
codex_patch() {
    jq -cn --arg c "$(printf "apply_patch <<'EOF'\n*** Begin Patch\n%s\n*** End Patch\nEOF" "$1")" \
        '{turn_id: "t1", tool_name: "apply_patch", tool_use_id: "c1", tool_input: {command: $c}}'
}
# Real Codex form: the BARE envelope, no "apply_patch" wrapper literal in the
# command (tool_name carries the identity) — the shape a live capture showed.
codex_patch_bare() {
    jq -cn --arg c "$(printf '*** Begin Patch\n%s\n*** End Patch' "$1")" \
        '{turn_id: "t1", tool_name: "apply_patch", tool_use_id: "c1", tool_input: {command: $c}}'
}

run 2 "Codex shell: cat .env denied"             "$(codex_shell "cat $WORK/.env")"
run 2 "Codex shell: compound command denied"     "$(codex_shell "ls -la && cat $WORK/auth.json")"
run 2 "Codex shell: key file behind a flag denied" "$(codex_shell "openssl rsa -in $WORK/id_rsa -check")"
run 2 "Codex shell: symlink token resolved and denied" "$(codex_shell "cat $WORK/notes.md")"
run 2 "Codex shell: argv-array command denied"   "$(jq -cn --arg c "cat $WORK/.env" '{tool_input: {command: ["bash", "-lc", $c]}}')"
run 0 "Codex shell: .env.example allowed"        "$(codex_shell "cat $WORK/.env.example")"
run 0 "Codex shell: innocent command allowed"    "$(codex_shell "git status && ls src/")"

# --- Codex layout: apply_patch envelopes (write-side denial) ---
run 2 "Codex patch: Update File .env denied"     "$(codex_patch "*** Update File: $WORK/.env
@@
+SECRET=2")"
run 2 "Codex patch: unquoted heredoc denied"     "$(jq -cn --arg c "$(printf 'apply_patch <<EOF\n*** Begin Patch\n*** Update File: %s\n*** End Patch\nEOF' "$WORK/.env")" '{tool_input: {command: $c}}')"
run 2 "Codex patch: direct-argument form denied" "$(jq -cn --arg c "$(printf "apply_patch '*** Begin Patch\n*** Update File: %s\n*** End Patch'" "$WORK/.env")" '{tool_input: {command: $c}}')"
run 2 "Codex patch: multi-file, secret second"   "$(codex_patch "*** Update File: $WORK/config.php
@@
+x
*** Update File: $WORK/.env
@@
+y")"
run 2 "Codex patch: rename onto .env denied"     "$(codex_patch "*** Update File: $WORK/config.php
*** Move to: $WORK/.env")"
run 0 "Codex patch: body mentioning .env allowed (envelope stripped)" "$(codex_patch "*** Update File: $WORK/notes-about-env.md
@@
+See .env for configuration")"
# Direct-argument form puts '*** Begin Patch' mid-line after the quote —
# the strip must still engage or the body's .env token would false-deny.
run 0 "Codex patch: direct-arg body mentioning .env allowed" "$(jq -cn --arg c "$(printf "apply_patch '*** Begin Patch\n*** Update File: %s\n@@\n+See .env for configuration\n*** End Patch'" "$WORK/notes-about-env.md")" '{tool_input: {command: $c}}')"
run 0 "Codex patch: ordinary file allowed"       "$(codex_patch "*** Update File: $WORK/config.php
@@
+x")"
# Real Codex form (bare envelope, no "apply_patch" literal): the write-side
# denial rides on hook_affected_files, so the bare shape must engage too.
run 2 "Codex bare patch: Update File .env denied" "$(codex_patch_bare "*** Update File: $WORK/.env
@@
+SECRET=2")"
run 0 "Codex bare patch: ordinary file allowed"   "$(codex_patch_bare "*** Update File: $WORK/config.php
@@
+x")"
run 0 "Codex bare patch: body mentioning .env allowed (envelope stripped)" "$(codex_patch_bare "*** Update File: $WORK/notes-about-env.md
@@
+See .env for configuration")"
# A plain shell command that merely CONTAINS patch text (tool_name shell, no
# "apply_patch" literal — a heredoc writing a .patch file) must not fail-close
# even when the patch body's Update-File header names a secret (PR #6 review):
# the file-header layer only fires for real apply_patch events, and the token
# scan strips the envelope before scanning.
run 0 "Codex shell: patch text mentioning .env in a heredoc not denied" "$(jq -cn --arg c "$(printf 'cat > demo.patch <<PATCH\n*** Begin Patch\n*** Update File: %s\n@@\n+SECRET=2\n*** End Patch\nPATCH' "$WORK/.env")" '{turn_id: "t1", tool_name: "shell", tool_use_id: "c1", tool_input: {command: $c}}')"

# --- harness.conf is the authoritative pattern source ---
# A tailored conf fully replaces the defaults: its own globs deny/allow, and
# patterns absent from it (like .env) no longer match.
CONF_ROOT="$WORK/conf-root"
mkdir -p "$CONF_ROOT/scripts/hooks"
cp "$(dirname "$HOOK")/lib.sh" "$CONF_ROOT/scripts/hooks/lib.sh"
cp "$HOOK" "$CONF_ROOT/scripts/hooks/guard-secrets.sh"
cat > "$CONF_ROOT/scripts/harness.conf" <<'EOF'
SECRET_PATTERNS="mysecret.*"
SECRET_ALLOW_PATTERNS="mysecret.example"
EOF
CONF_HOOK="$CONF_ROOT/scripts/hooks/guard-secrets.sh"
run_conf() {
    local expected="$1" desc="$2" payload="$3" actual
    printf '%s' "$payload" | "$CONF_HOOK" >/dev/null 2>&1
    actual=$?
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $desc — expected exit $expected, got $actual"
        fails=$((fails + 1))
    else
        echo "ok:   $desc"
    fi
}
run_conf 2 "conf pattern mysecret.txt denied"     "$(payload "$WORK/mysecret.txt")"
run_conf 0 "conf allow mysecret.example allowed"  "$(payload "$WORK/mysecret.example")"
run_conf 0 "conf replaces defaults (.env allowed under custom conf)" "$(payload "$WORK/.env")"

# --- observability: a deny appends one valid JSON line; HARNESS_LOG=0 doesn't ---
LOG="$WORK/log.jsonl"
printf '%s' "$(payload "$WORK/.env")" | env HARNESS_LOG=1 HARNESS_LOG_FILE="$LOG" "$HOOK" >/dev/null 2>&1
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" | tr -d '[:space:]')" = "1" ] \
    && jq -e 'select(.event == "deny" and .hook == "guard-secrets.sh")' "$LOG" >/dev/null 2>&1; then
    echo "ok:   deny appends one valid JSON log line"
else
    echo "FAIL: deny did not append one valid JSON log line"
    fails=$((fails + 1))
fi
printf '%s' "$(payload "$WORK/.env")" | env HARNESS_LOG=0 HARNESS_LOG_FILE="$WORK/off.jsonl" "$HOOK" >/dev/null 2>&1
if [ -e "$WORK/off.jsonl" ]; then
    echo "FAIL: HARNESS_LOG=0 must not write a log"
    fails=$((fails + 1))
else
    echo "ok:   HARNESS_LOG=0 writes nothing"
fi

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails guard-secrets case(s)"
    exit 1
fi
echo "PASSED: all guard-secrets cases"
