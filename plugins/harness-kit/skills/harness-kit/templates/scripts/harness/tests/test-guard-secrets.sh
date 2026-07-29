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

HOOK="$(cd "$(dirname "$0")/../hooks" && pwd)/guard-secrets.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-guard-secrets.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

# Keep hook_log out of the repo during tests; explicit log cases opt back in.
export HARNESS_LOG=0

fails=0
skips=0

# skip <reason> — a fixture this environment cannot build. Reported, counted,
# and surfaced in the summary: a case that silently vanishes is worse than one
# that fails, because the suite would still print PASSED.
skip() {
    echo "SKIP: $1"
    skips=$((skips + 1))
}

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

# Symlink capability probe. Windows without Developer Mode (and an unprivileged
# Git Bash) cannot create real symlinks: MSYS `ln -s` silently COPIES instead
# and still exits 0, so a successful `ln` is NOT proof — the [ -L ] test is what
# separates a real link from a copy.
#
# This matters more than portability housekeeping. Without the probe, a copy
# named notes.md is an ordinary file with an innocuous name, the guard
# correctly allows it, and the suite reports
#     FAIL: symlink notes.md->.env denied — expected exit 2, got 0
# which reads exactly like the secret guard letting a symlink through. A
# maintainer would chase a phantom guard bypass. A fixture that cannot be built
# must SKIP loudly; it must never assert against the degraded state.
HAVE_SYMLINKS=0
if ln -s "$WORK/.env" "$WORK/.symprobe" 2>/dev/null && [ -L "$WORK/.symprobe" ]; then
    HAVE_SYMLINKS=1
fi
rm -f "$WORK/.symprobe"

if [ "$HAVE_SYMLINKS" -eq 1 ]; then
    ln -s "$WORK/.env"         "$WORK/notes.md"          # innocuous name -> secret
    ln -s "$WORK/.env"         "$WORK/.env.example.link" # allow-ish name -> secret
    ln -s "$WORK/.env.example" "$WORK/safe.link"         # -> example (safe)
fi

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
run 2 "id_ecdsa denied"              "$(payload "$WORK/id_ecdsa")"
run 2 "id_dsa denied"                "$(payload "$WORK/id_dsa")"
run 2 ".git-credentials denied"      "$(payload "$WORK/.git-credentials")"
run 2 "putty key.ppk denied"         "$(payload "$WORK/key.ppk")"
run 2 "java keystore.jks denied"     "$(payload "$WORK/keystore.jks")"
run 2 "Cursor layout .env denied"    "$(cursor_payload "$WORK/.env")"
run 2 "Grep path at .env denied"     "$(grep_payload "$WORK/.env")"

# --- deny: symlink laundering ---
if [ "$HAVE_SYMLINKS" -eq 1 ]; then
    run 2 "symlink notes.md->.env denied"          "$(payload "$WORK/notes.md")"
    run 2 "symlink .env.example.link->.env denied" "$(payload "$WORK/.env.example.link")"
else
    # One skip per lost ASSERTION, not per block: the summary count is a
    # coverage-gap number and must not understate it.
    skip "symlink notes.md->.env denied — this filesystem cannot create symlinks"
    skip "symlink .env.example.link->.env denied — this filesystem cannot create symlinks"
fi

# --- allow: safe files (HOOK LAYER ONLY) ---
# These pin the hook's allow-precedence, NOT whole-system readability. The
# generated Claude Code deny list is deny-only (ADR 011), so the default
# `.env.*` pattern denies `.env.example` natively there no matter what passes
# here. Do not read a green run as "the allow list works everywhere".
run 0 ".env.example allowed (hook)"  "$(payload "$WORK/.env.example")"
run 0 ".env.sample allowed"          "$(payload "$WORK/.env.sample")"
run 0 ".env.testing allowed"         "$(payload "$WORK/.env.testing")"
run 0 ".env.mcp.example allowed"     "$(payload "$WORK/.env.mcp.example")"
if [ "$HAVE_SYMLINKS" -eq 1 ]; then
    run 0 "symlink safe.link->example allowed" "$(payload "$WORK/safe.link")"
else
    skip "symlink allow-precedence — this filesystem cannot create symlinks"
fi
run 0 "ordinary source file allowed" "$(payload "$WORK/config.php")"
run 0 "Grep on directory allowed"    "$(grep_payload "$WORK")"
# A Grep whose optional `path` is omitted means "search the project". Like the
# directory case above it names no file, so it is allowed BY DESIGN, not by
# oversight — denying it would deny nearly every search the agent makes. These
# two cases are the documented edge of this hook's search coverage (see the
# guard-secrets.sh header); pin them so a future "tighten Grep" change has to
# confront the trade-off deliberately instead of shipping an unusable agent.
run 0 "Grep with no path allowed"    '{"tool_name":"Grep","tool_input":{"pattern":"BEGIN PRIVATE KEY"}}'
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
if [ "$HAVE_SYMLINKS" -eq 1 ]; then
    run 2 "Codex shell: symlink token resolved and denied" "$(codex_shell "cat $WORK/notes.md")"
else
    skip "Codex shell symlink resolution — this filesystem cannot create symlinks"
fi
run 2 "Codex shell: argv-array command denied"   "$(jq -cn --arg c "cat $WORK/.env" '{tool_input: {command: ["bash", "-lc", $c]}}')"
run 0 "Codex shell: .env.example allowed"        "$(codex_shell "cat $WORK/.env.example")"
run 0 "Codex shell: innocent command allowed"    "$(codex_shell "git status && ls src/")"

# --- Claude Code layout: Bash commands ---
# WHAT THESE DO AND DO NOT PIN. `hook_command_string` (lib.sh) reads
# `tool_input.command` without consulting `tool_name`, so these traverse the
# SAME path as the Codex shell cases above: they do NOT prove `Bash` is in the
# Claude matcher and would still pass if it were removed. That wiring is pinned
# by check #8d in lib/check-instructions.sh, whose tuple requires every token of
# `Read|Grep|Bash`. Kept here are only the two cases that add signal over the
# Codex block — a SECRET_PATTERNS entry reached through a command, and the
# documented false positive.
claude_bash() {
    jq -cn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}'
}

run 2 "Claude Bash: keystore behind a flag denied" "$(claude_bash "keytool -list -keystore $WORK/keystore.jks")"
run 2 "Claude Bash: a command that only NAMES a secret is denied (documented false positive)" \
    "$(claude_bash "git commit -m 'clarify .env handling'")"
run 0 "Claude Bash: innocent command allowed"    "$(claude_bash "git status && ls src/")"

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
mkdir -p "$CONF_ROOT/scripts/harness/hooks"
cp "$(dirname "$HOOK")/lib.sh" "$CONF_ROOT/scripts/harness/hooks/lib.sh"
cp "$HOOK" "$CONF_ROOT/scripts/harness/hooks/guard-secrets.sh"
cat > "$CONF_ROOT/scripts/harness/harness.conf" <<'EOF'
SECRET_PATTERNS="mysecret.*"
SECRET_ALLOW_PATTERNS="mysecret.example"
EOF
CONF_HOOK="$CONF_ROOT/scripts/harness/hooks/guard-secrets.sh"
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
obs_payload=$(printf '%s' "$(payload "$WORK/.env")" | jq -c '.session_id="payload-session"')
printf '%s' "$obs_payload" | env HARNESS_LOG=1 HARNESS_LOG_FILE="$LOG" \
    HARNESS_PROVIDER=codex HARNESS_PLAN_SLUG=v017 "$HOOK" >/dev/null 2>&1
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" | tr -d '[:space:]')" = "1" ] \
    && jq -e 'select(.version == 2 and .event == "deny" and .hook == "guard-secrets.sh"
        and keys == ["context","data","detail","event","file","hook","ts","version"]
        and .context.session_id == "payload-session" and .context.provenance.session_id == "payload"
        and .context.provider == "codex" and .context.provenance.provider == "env"
        and .context.plan_slug == "v017" and .context.provenance.plan_slug == "env")' "$LOG" >/dev/null 2>&1; then
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
if [ "$skips" -gt 0 ]; then
    echo "PASSED: all guard-secrets cases that ran ($skips skipped — no symlink support)"
else
    echo "PASSED: all guard-secrets cases"
fi
