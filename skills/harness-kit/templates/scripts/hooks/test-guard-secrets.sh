#!/usr/bin/env bash
# Regression tests for guard-secrets.sh. Runnable standalone and in CI.
# Each case feeds a hook payload on stdin and asserts the exit code:
#   0 = allowed, 2 = denied.
#
# If you tailor the classify() lists in guard-secrets.sh, extend these cases
# to match — the test pins the deny boundary, including the symlink and
# case-folding behavior that is easy to regress.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

HOOK="$(cd "$(dirname "$0")" && pwd)/guard-secrets.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

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

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails guard-secrets case(s)"
    exit 1
fi
echo "PASSED: all guard-secrets cases"
