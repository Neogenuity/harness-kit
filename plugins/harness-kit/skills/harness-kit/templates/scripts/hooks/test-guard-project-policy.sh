#!/usr/bin/env bash
# Regression tests for guard-project-policy.sh (the advisory stop hook). Pins
# (a) the shipped skeleton stays a no-op / fails open, and (b) the clean-tree
# skip PATTERN the commented VERIFY example documents: the fast gates run only
# when the working tree is dirty, so a no-op stop pays no multi-second tax.
# A spy verify.sh (marker outside the repo, so it never dirties the tree)
# proves invocation vs skip.
set -uo pipefail

command -v git >/dev/null 2>&1 || { echo "SKIP: git not available"; exit 0; }
HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fails=0

# --- (a) shipped skeleton: no-op / fail-open ---
mkdir -p "$WORK/skel/scripts/hooks"
cp "$HOOKS_DIR/lib.sh" "$WORK/skel/scripts/hooks/lib.sh"
cp "$HOOKS_DIR/guard-project-policy.sh" "$WORK/skel/scripts/hooks/guard-project-policy.sh"
( cd "$WORK/skel" && git init -q . && git config user.email t@e.invalid && git config user.name t \
    && git commit -q --allow-empty -m seed >/dev/null )
printf '{}' | "$WORK/skel/scripts/hooks/guard-project-policy.sh" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && echo "ok:   shipped skeleton is a no-op (exit 0, empty payload)" \
    || { echo "FAIL: skeleton should exit 0 (rc=$rc)"; fails=$((fails+1)); }

# --- (b) clean-tree skip PATTERN with a spy verify.sh ---
export SPY_MARKER="$WORK/verify-invoked"     # outside the repo -> never dirties it
REPO="$WORK/repo"; mkdir -p "$REPO/scripts/hooks"
cp "$HOOKS_DIR/lib.sh" "$REPO/scripts/hooks/lib.sh"
cat > "$REPO/scripts/verify.sh" <<'V'
#!/usr/bin/env bash
touch "${SPY_MARKER:-/tmp/gpp-spy}"
exit 0
V
chmod +x "$REPO/scripts/verify.sh"
cat > "$REPO/scripts/hooks/guard-project-policy.sh" <<'P'
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
hook_read_input
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT" || exit 0
command -v git >/dev/null 2>&1 || exit 0
warnings=""
append() { warnings="${warnings}$1"$'\n'; }
if [ -x scripts/verify.sh ] && [ -n "$(git status --porcelain 2>/dev/null)" ] \
        && ! out=$(bash scripts/verify.sh --fast 2>&1); then
    append "VERIFY WARNING: $out"
fi
[ -n "$warnings" ] || exit 0
hook_advise_once "$warnings"
P
chmod +x "$REPO/scripts/hooks/guard-project-policy.sh"
( cd "$REPO" && git init -q . && git config user.email t@e.invalid && git config user.name t \
    && git add -A && git commit -qm seed >/dev/null )
PH="$REPO/scripts/hooks/guard-project-policy.sh"

# clean tree -> verify NOT invoked
rm -f "$SPY_MARKER"; printf '{}' | "$PH" >/dev/null 2>&1
[ ! -f "$SPY_MARKER" ] && echo "ok:   clean tree -> verify.sh is NOT invoked (skip)" \
    || { echo "FAIL: clean tree should skip verify.sh"; fails=$((fails+1)); }

# dirty tree -> verify invoked
echo dirty > "$REPO/newfile.txt"
rm -f "$SPY_MARKER"; printf '{}' | "$PH" >/dev/null 2>&1
[ -f "$SPY_MARKER" ] && echo "ok:   dirty tree -> verify.sh IS invoked" \
    || { echo "FAIL: dirty tree should invoke verify.sh"; fails=$((fails+1)); }

# fail-open: verify.sh absent -> hook still exits 0
rm -f "$REPO/scripts/verify.sh"
printf '{}' | "$PH" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && echo "ok:   missing verify.sh -> hook still exits 0 (fail-open)" \
    || { echo "FAIL: should exit 0 when verify.sh absent (rc=$rc)"; fails=$((fails+1)); }

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails guard-project-policy case(s)"; exit 1; fi
echo "PASSED: all guard-project-policy cases"
