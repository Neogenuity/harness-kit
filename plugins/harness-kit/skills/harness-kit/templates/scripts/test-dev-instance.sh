#!/usr/bin/env bash
# Regression tests for dev-instance.sh. Runnable standalone and in CI.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER="$SCRIPTS_DIR/dev-instance.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dev-instance-test.XXXXXX") || exit 1
trap 'git -C "$MAIN" worktree remove --force "$LINKED" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

fails=0
pass() { printf 'ok:   %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; fails=$((fails + 1)); }

git_c() { git -c user.email=t@example.com -c user.name=t "$@"; }
MAIN="$WORK/main"
LINKED="$WORK/linked"
mkdir -p "$MAIN"
( cd "$MAIN" && git init -q && printf 'fixture\n' > tracked.txt \
    && git_c add tracked.txt && git_c commit -qm init )
git -C "$MAIN" worktree add -q -b linked-fixture "$LINKED"

main_a=$(cd "$MAIN" && "$HELPER" suffix)
main_b=$(cd "$MAIN" && "$HELPER" suffix)
[ "$main_a" = "$main_b" ] \
    && pass "suffix: stable for repeated calls" \
    || fail "suffix: repeated calls changed identity ($main_a != $main_b)"
if printf '%s\n' "$main_a" | grep -qE '^h[0-9a-f]{12}$'; then
    pass "suffix: shape is h plus 12 lowercase SHA-256 characters"
else
    fail "suffix: invalid shape" "$main_a"
fi

ln -s "$MAIN" "$WORK/main-alias"
alias_suffix=$(cd "$WORK/main-alias" && "$HELPER" suffix)
[ "$alias_suffix" = "$main_a" ] \
    && pass "suffix: symlinked checkout resolves to the same physical root" \
    || fail "suffix: physical-root resolution changed through a symlink"

linked_suffix=$(cd "$LINKED" && "$HELPER" suffix)
[ "$linked_suffix" != "$main_a" ] \
    && pass "suffix: linked worktree gets a distinct identity" \
    || fail "suffix: linked worktree collided with the main worktree"

api_suffix=$(cd "$MAIN" && "$HELPER" suffix api)
[ "$api_suffix" != "$main_a" ] \
    && pass "suffix: namespace changes identity" \
    || fail "suffix: namespace did not change identity"

# NUL-delimited tuple hashing prevents the ambiguity in newline serialization:
# root=A + namespace=$'x\ny' and root=$'A\nx' + namespace=y used to feed the
# same byte stream to SHA-256. Both are legal filesystem/input strings.
AMBIG_A="$WORK/ambiguous"
AMBIG_B=$(printf '%s\nx' "$AMBIG_A")
mkdir -p "$AMBIG_A" "$AMBIG_B"
( cd "$AMBIG_A" && git init -q )
( cd "$AMBIG_B" && git init -q )
ambig_ns=$(printf 'x\ny')
ambig_a=$(cd "$AMBIG_A" && "$HELPER" suffix "$ambig_ns")
ambig_b=$(cd "$AMBIG_B" && "$HELPER" suffix y)
[ "$ambig_a" != "$ambig_b" ] \
    && pass "suffix: root/namespace tuple is separator-unambiguous" \
    || fail "suffix: ambiguous root/namespace tuples collided"

port_a=$(cd "$MAIN" && "$HELPER" port 20000 1000)
port_b=$(cd "$MAIN" && "$HELPER" port 20000 1000 app)
if [ "$port_a" = "$port_b" ] && [ "$port_a" -ge 20000 ] && [ "$port_a" -le 20999 ]; then
    pass "port: stable default namespace candidate stays inside [base, base+span)"
else
    fail "port: unstable or out-of-range candidate" "$port_a / $port_b"
fi
[ "$(cd "$MAIN" && "$HELPER" port 1024 1)" = 1024 ] \
    && pass "port: span=1 returns the base" \
    || fail "port: span=1 did not return the base"
[ "$(cd "$MAIN" && "$HELPER" port 65535 1)" = 65535 ] \
    && pass "port: upper boundary 65535 is accepted" \
    || fail "port: upper boundary was not accepted"

expect_fail() {
    local desc="$1" needle="$2"; shift 2
    local out rc
    out=$("$@" 2>&1); rc=$?
    if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qiF "$needle"; then
        pass "$desc"
    else
        fail "$desc (rc=$rc, expected message containing '$needle')" "$out"
    fi
}

expect_fail "args: unknown command rejected" "usage:" bash -c 'cd "$1" && "$2" wat' _ "$MAIN" "$HELPER"
expect_fail "args: suffix extra argument rejected" "usage:" bash -c 'cd "$1" && "$2" suffix a b' _ "$MAIN" "$HELPER"
expect_fail "args: port missing span rejected" "usage:" bash -c 'cd "$1" && "$2" port 20000' _ "$MAIN" "$HELPER"
expect_fail "args: port extra argument rejected" "usage:" bash -c 'cd "$1" && "$2" port 20000 10 app extra' _ "$MAIN" "$HELPER"
expect_fail "args: empty namespace rejected" "namespace must be non-empty" bash -c 'cd "$1" && "$2" suffix ""' _ "$MAIN" "$HELPER"
expect_fail "range: base below 1024 rejected" "base must" bash -c 'cd "$1" && "$2" port 1023 1' _ "$MAIN" "$HELPER"
expect_fail "range: zero span rejected" "span must" bash -c 'cd "$1" && "$2" port 20000 0' _ "$MAIN" "$HELPER"
expect_fail "range: non-integer rejected" "base must" bash -c 'cd "$1" && "$2" port nope 2' _ "$MAIN" "$HELPER"
expect_fail "range: candidate range above 65535 rejected" "<= 65535" bash -c 'cd "$1" && "$2" port 65535 2' _ "$MAIN" "$HELPER"
expect_fail "range: giant integer rejected without overflow" "base must" bash -c 'cd "$1" && "$2" port 999999999999999999999 1' _ "$MAIN" "$HELPER"

OUTSIDE="$WORK/outside"; mkdir -p "$OUTSIDE"
expect_fail "environment: outside Git fails clearly" "not inside a Git worktree" bash -c 'cd "$1" && "$2" suffix' _ "$OUTSIDE" "$HELPER"

GIT_BIN=$(command -v git)
if command -v shasum >/dev/null 2>&1; then
    HASH_NAME=shasum; HASH_BIN=$(command -v shasum)
else
    HASH_NAME=sha256sum; HASH_BIN=$(command -v sha256sum)
fi
NO_GIT="$WORK/no-git"; mkdir -p "$NO_GIT"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$HASH_BIN" > "$NO_GIT/$HASH_NAME"
chmod +x "$NO_GIT/$HASH_NAME"
expect_fail "environment: missing git fails clearly" "git is required" env PATH="$NO_GIT" "$BASH" -c 'cd "$1" && "$2" "$3" suffix' _ "$MAIN" "$BASH" "$HELPER"

NO_HASH="$WORK/no-hash"; mkdir -p "$NO_HASH"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$GIT_BIN" > "$NO_HASH/git"
chmod +x "$NO_HASH/git"
expect_fail "environment: missing hash tool fails clearly" "SHA-256 tool is required" env PATH="$NO_HASH" "$BASH" -c 'cd "$1" && "$2" "$3" suffix' _ "$MAIN" "$BASH" "$HELPER"

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails dev-instance case(s)"
    exit 1
fi
echo "PASSED: all dev-instance cases"
