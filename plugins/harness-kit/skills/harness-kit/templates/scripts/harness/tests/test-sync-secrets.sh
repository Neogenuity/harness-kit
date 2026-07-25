#!/usr/bin/env bash
# test-sync-secrets.sh — `sync secrets [--check]` native deny-mirror generation.
# Builds a throwaway fixture with a settings.json / opencode.json that are
# missing some SECRET_PATTERNS denies (plus a non-secret deny and an OpenCode
# allow to prove preservation), then drives the shipped sync command and
# asserts: --check flags the drift, write reconciles it (ensure-present +
# preserve), --check then passes, a removed entry re-drifts, and an unwired
# provider is never touched. jq-gated (sync secrets hard-requires jq); skipped
# without it, like the other jq-dependent shipped checks.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")/../.." && pwd)"   # .../scripts
SYNC="$SCRIPTS_DIR/harness/sync"

if ! command -v jq >/dev/null 2>&1; then
    echo "ok:   $(basename "$0") skipped (jq unavailable — sync secrets is jq-gated)"
    exit 0
fi

# Guarded mktemp: bare `mktemp -d` ignores $TMPDIR on macOS and fails in a
# sandbox; an empty path turns `cd ""` into a silent no-op in the HOST repo.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-sync-secrets.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

# new_fixture <harness_providers> — a minimal tree the sync command runs in:
# the sync wrapper + the libs it sources + a harness.conf, plus provider
# configs deliberately missing some secret denies.
new_fixture() {
    local w hp="$1"
    w=$(mktemp -d "$WORK/fx.XXXXXX") || return 1
    mkdir -p "$w/scripts/harness/lib" "$w/.claude"
    cp "$SYNC" "$w/scripts/harness/sync"
    cp "$SCRIPTS_DIR/harness/lib/sync-lib.sh" "$w/scripts/harness/lib/"
    cp "$SCRIPTS_DIR/harness/lib/provider-lib.sh" "$w/scripts/harness/lib/"
    cp "$SCRIPTS_DIR/harness/lib/provider-caps" "$w/scripts/harness/lib/"
    chmod +x "$w/scripts/harness/sync"
    {
        printf 'HARNESS_PROVIDERS="%s"\n' "$hp"
        printf 'SECRET_PATTERNS=".env .env.* auth.json credentials.json *.pem id_rsa id_ed25519"\n'
    } > "$w/scripts/harness/harness.conf"
    cat > "$w/.claude/settings.json" <<'JSON'
{ "companyKey": "keep-me",
  "permissions": { "deny": [ "Read(./.env)", "Read(**/.env)", "Read(./secrets/prod.key)" ] } }
JSON
    cat > "$w/opencode.json" <<'JSON'
{ "permission": { "read": { "**/.env": "deny", "**/.env.example": "allow" } }, "otherKey": 1 }
JSON
    printf '%s' "$w"
}

# --- drift detected, reconciled, idempotent ---------------------------------
W=$(new_fixture ".claude .opencode")
if bash "$W/scripts/harness/sync" secrets --check >/dev/null 2>&1; then
    fail "sync secrets --check flags a config missing secret denies"
else
    pass "sync secrets --check flags a config missing secret denies"
fi

out=$(bash "$W/scripts/harness/sync" secrets 2>&1); rc=$?
[ "$rc" -eq 0 ] && pass "sync secrets (write) succeeds" || { fail "sync secrets (write) succeeds"; printf '%s\n' "$out" | sed 's/^/        /'; }

# Every SECRET_PATTERN now has both Read(./P) and Read(**/P); the non-secret
# deny and the unrelated key survive.
if jq -e '
    .companyKey == "keep-me"
    and (.permissions.deny | index("Read(./secrets/prod.key)") != null)
    and (.permissions.deny | index("Read(**/auth.json)") != null)
    and (.permissions.deny | index("Read(./id_ed25519)") != null)
' "$W/.claude/settings.json" >/dev/null 2>&1; then
    pass "claude: secret denies added, non-secret deny + unrelated key preserved"
    # The Claude mirror is DENY-ONLY (ADR 011) — the platform resolves
    # deny-beats-allow, so an allow entry would be inert and misleading. The
    # harness.conf comment, hooks/README.md, and ADR 011 all rest on this
    # invariant; pin it executably so a future generator change cannot quietly
    # start emitting SECRET_ALLOW_PATTERNS here.
    if jq -e '(.permissions.allow // []) | length == 0' "$W/.claude/settings.json" >/dev/null 2>&1; then
        pass "claude: mirror stays deny-only (no allow entries generated)"
    else
        fail "claude: mirror stays deny-only (no allow entries generated)"
    fi
else
    fail "claude: secret denies added, non-secret deny + unrelated key preserved"
fi

# OpenCode gets the deny keys; its hand-owned allow exception and unrelated key
# survive.
if jq -e '
    .otherKey == 1
    and (.permission.read["**/.env.example"] == "allow")
    and (.permission.read["**/auth.json"] == "deny")
    and (.permission.read["**/id_rsa"] == "deny")
' "$W/opencode.json" >/dev/null 2>&1; then
    pass "opencode: deny keys added, allow exception + unrelated key preserved"
else
    fail "opencode: deny keys added, allow exception + unrelated key preserved"
fi

if bash "$W/scripts/harness/sync" secrets --check >/dev/null 2>&1; then
    pass "sync secrets --check is clean after reconciliation (idempotent)"
else
    fail "sync secrets --check is clean after reconciliation (idempotent)"
fi

# --- a hand-removed deny re-drifts ------------------------------------------
jq '.permissions.deny -= ["Read(**/auth.json)"]' "$W/.claude/settings.json" > "$W/.claude/s" \
    && mv "$W/.claude/s" "$W/.claude/settings.json"
if bash "$W/scripts/harness/sync" secrets --check >/dev/null 2>&1; then
    fail "sync secrets --check re-flags a hand-removed deny entry"
else
    pass "sync secrets --check re-flags a hand-removed deny entry"
fi

# --- an unwired provider is never touched -----------------------------------
W2=$(new_fixture ".claude")   # .opencode NOT wired
before=$(cat "$W2/opencode.json")
bash "$W2/scripts/harness/sync" secrets >/dev/null 2>&1
if [ "$before" = "$(cat "$W2/opencode.json")" ]; then
    pass "an unwired provider's config is left untouched"
else
    fail "an unwired provider's config is left untouched"
fi

# --- the target file's existing layout survives a reconcile ------------------
# jq renders 2-space by default, so writing its output back reindented the
# WHOLE document: the deny delta got buried in formatting churn in an adopter's
# hand-formatted config. Indentation is a property of the file we are editing,
# not of the tool doing the edit.
#
# indent_of <file> — leading-space count of the first indented line, or `tab`.
indent_of() {
    awk 'NR > 1 && /^[ \t]/ {
            if (substr($0, 1, 1) == "\t") { print "tab"; exit }
            print match($0, /[^ ]/) - 1; exit
         }' "$1"
}

W3=$(new_fixture ".claude .opencode")
# Re-render both configs 4-space, the style jq would otherwise flatten to 2.
for f in "$W3/.claude/settings.json" "$W3/opencode.json"; do
    jq --indent 4 . "$f" > "$f.4sp" && mv "$f.4sp" "$f"
done
bash "$W3/scripts/harness/sync" secrets >/dev/null 2>&1
for f in "$W3/.claude/settings.json" "$W3/opencode.json"; do
    got=$(indent_of "$f")
    if [ "$got" = 4 ]; then
        pass "$(basename "$f"): 4-space indentation survives reconcile"
    else
        fail "$(basename "$f"): 4-space indentation survives reconcile (got '$got')"
    fi
done

# The denies must still have landed — preserving layout must not cost content.
if jq -e '(.permissions.deny | index("Read(**/auth.json)")) != null' "$W3/.claude/settings.json" >/dev/null 2>&1; then
    pass "layout preservation does not skip the deny additions"
else
    fail "layout preservation does not skip the deny additions"
fi

# Idempotency: the write path compares jq's rendering against the file bytes,
# so before this fix a 4-space file NEVER matched and every run rewrote it and
# reported "reconciled". A second run must now be a no-op.
# Re-render 4-space FIRST: the reconcile above already normalized the file, so
# without this the second run would trivially match under either behavior and
# this case would pin nothing.
for f in "$W3/.claude/settings.json" "$W3/opencode.json"; do
    jq --indent 4 . "$f" > "$f.4sp" && mv "$f.4sp" "$f"
done
before=$(cat "$W3/.claude/settings.json")
out=$(bash "$W3/scripts/harness/sync" secrets 2>&1)
if [ "$before" = "$(cat "$W3/.claude/settings.json")" ]; then
    pass "a second reconcile of an already-current 4-space file is a no-op"
else
    fail "a second reconcile of an already-current 4-space file is a no-op"
fi
# Name the FILE in the pattern: a bare "already current" match is satisfied by
# whichever provider happens to be clean, and would pass under either behavior.
case "$out" in
    *".claude/settings.json already current"*)
        pass "an already-current 4-space file reports 'already current'" ;;
    *)  fail "an already-current 4-space file reports 'already current' (got: $out)" ;;
esac

# Tabs are a layout too.
W4=$(new_fixture ".claude .opencode")
jq --tab . "$W4/.claude/settings.json" > "$W4/.claude/s" && mv "$W4/.claude/s" "$W4/.claude/settings.json"
bash "$W4/scripts/harness/sync" secrets >/dev/null 2>&1
if [ "$(indent_of "$W4/.claude/settings.json")" = tab ]; then
    pass "tab indentation survives reconcile"
else
    fail "tab indentation survives reconcile"
fi

if [ "$fails" -eq 0 ]; then
    echo "PASSED: sync secrets mirror generation"
    exit 0
fi
echo "FAILED: $fails sync-secrets case(s)"
exit 1
