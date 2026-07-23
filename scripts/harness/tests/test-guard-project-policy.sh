#!/usr/bin/env bash
# Regression tests for guard-project-policy.sh (the advisory stop hook). Pins
# (a) the shipped skeleton stays a no-op / fails open, and (b) the clean-tree
# skip PATTERN the commented VERIFY example documents: the fast gates run only
# when the working tree is dirty, so a no-op stop pays no multi-second tax.
# A spy verify.sh (marker outside the repo, so it never dirties the tree)
# proves invocation vs skip.
set -uo pipefail

command -v git >/dev/null 2>&1 || { echo "SKIP: git not available"; exit 0; }
HOOKS_DIR="$(cd "$(dirname "$0")/../hooks" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-guard-project-policy.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
fails=0

# The policy hook's template home differs from its installed home: shipped
# from the kit's hooks/ template dir, installed at .harness/hooks/. Resolve
# whichever this checkout provides so the suite runs from both layouts.
GPP=""
for c in "$(dirname "$0")/../../../.harness/hooks/guard-project-policy.sh" \
         "$(dirname "$0")/../../hooks/guard-project-policy.sh"; do
    [ -f "$c" ] && { GPP="$c"; break; }
done
[ -n "$GPP" ] || { echo "FAIL: guard-project-policy.sh not found in either layout"; exit 1; }

# --- (a) shipped skeleton: no-op / fail-open ---
mkdir -p "$WORK/skel/scripts/harness/hooks" "$WORK/skel/.harness/hooks"
cp "$HOOKS_DIR/lib.sh" "$WORK/skel/scripts/harness/hooks/lib.sh"
cp "$GPP" "$WORK/skel/.harness/hooks/guard-project-policy.sh"
( cd "$WORK/skel" && git init -q . && git config user.email t@e.invalid && git config user.name t \
    && git commit -q --allow-empty -m seed >/dev/null )
printf '{}' | "$WORK/skel/.harness/hooks/guard-project-policy.sh" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && echo "ok:   shipped skeleton is a no-op (exit 0, empty payload)" \
    || { echo "FAIL: skeleton should exit 0 (rc=$rc)"; fails=$((fails+1)); }

# --- (b) clean-tree skip PATTERN with a spy verify.sh ---
export SPY_MARKER="$WORK/verify-invoked"     # outside the repo -> never dirties it
REPO="$WORK/repo"; mkdir -p "$REPO/scripts/harness/hooks" "$REPO/.harness/hooks"
cp "$HOOKS_DIR/lib.sh" "$REPO/scripts/harness/hooks/lib.sh"
cat > "$REPO/scripts/harness/verify" <<'V'
#!/usr/bin/env bash
touch "${SPY_MARKER:-/tmp/gpp-spy}"
exit 0
V
chmod +x "$REPO/scripts/harness/verify"
cat > "$REPO/.harness/hooks/guard-project-policy.sh" <<'P'
#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/../../scripts/harness/hooks/lib.sh" 2>/dev/null || exit 0
hook_read_input
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT" || exit 0
command -v git >/dev/null 2>&1 || exit 0
warnings=""
append() { warnings="${warnings}$1"$'\n'; }
if [ -x scripts/harness/verify ] && [ -n "$(git status --porcelain 2>/dev/null)" ] \
        && ! out=$(bash scripts/harness/verify --fast 2>&1); then
    append "VERIFY WARNING: $out"
fi
[ -n "$warnings" ] || exit 0
hook_advise_once "$warnings"
P
chmod +x "$REPO/.harness/hooks/guard-project-policy.sh"
( cd "$REPO" && git init -q . && git config user.email t@e.invalid && git config user.name t \
    && git add -A && git commit -qm seed >/dev/null )
PH="$REPO/.harness/hooks/guard-project-policy.sh"

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
rm -f "$REPO/scripts/harness/verify"
printf '{}' | "$PH" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && echo "ok:   missing verify.sh -> hook still exits 0 (fail-open)" \
    || { echo "FAIL: should exit 0 when verify.sh absent (rc=$rc)"; fails=$((fails+1)); }

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails guard-project-policy case(s)"; exit 1; fi
echo "PASSED: all guard-project-policy cases"
