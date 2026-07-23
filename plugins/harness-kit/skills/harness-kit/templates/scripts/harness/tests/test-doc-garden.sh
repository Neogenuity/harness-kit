#!/usr/bin/env bash
set -uo pipefail
SCRIPTS_DIR="$(cd "$(dirname "$0")/../lib" && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-doc-garden.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
fails=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

mkdir -p "$WORK/repo/scripts/harness/lib" "$WORK/repo/docs"
cp "$SCRIPTS_DIR/doc-garden.sh" "$WORK/repo/scripts/harness/lib/doc-garden.sh"
git -C "$WORK/repo" init -q
git -C "$WORK/repo" config user.email test@example.invalid
git -C "$WORK/repo" config user.name Test
printf '# Old\n' > "$WORK/repo/docs/deleted.md"
git -C "$WORK/repo" add docs/deleted.md
git -C "$WORK/repo" commit -qm seed
git -C "$WORK/repo" rm -q docs/deleted.md
git -C "$WORK/repo" commit -qm delete
mkdir -p "$WORK/repo/docs"
cat > "$WORK/repo/README.md" <<'EOF'
# Home

[missing](docs/nope.md)
[inline comment does not hide this](docs/inline-missing.md) <!-- ordinary note -->
[bad anchor](docs/good.md#absent)
[good](docs/good.md#present-heading)
[escape](../outside.md)
Historical path: `docs/deleted.md`.
[future](docs/not-created.md#later) and `docs/deleted.md` <!-- doc-garden: planned --> (verified 2025-01).
[planned anchor still checked](docs/good.md#later) <!-- doc-garden: planned -->
Provider statement (verified 2025-01).
Provider statement with day precision (re-verified 2026-07-14).
Malformed provider statement (verified 2025-13).
<!--
[template placeholder](docs/placeholder.md)
`docs/deleted.md`
verified 2020-01
-->
```md
[fixture only](docs/also-missing.md)
`docs/deleted.md`
verified 2020-01
```
   ~~~md
[tilde fixture](docs/tilde-missing.md)
`docs/deleted.md`
verified 2020-01
   ~~~
  ````md
[indented fixture](docs/indented-missing.md)
`docs/deleted.md`
verified 2020-01
  ````
EOF
cat > "$WORK/repo/docs/good.md" <<'EOF'
# Present Heading
EOF
git -C "$WORK/repo" add README.md docs/good.md
git -C "$WORK/repo" commit -qm docs
printf '# Outside\n' > "$WORK/outside.md"

before=$(git -C "$WORK/repo" status --porcelain)
report=$(DOC_GARDEN_NOW=2026-07 bash "$WORK/repo/scripts/harness/lib/doc-garden.sh" \
    --repo "$WORK/repo" --format json --stale-months 6); rc=$?
after=$(git -C "$WORK/repo" status --porcelain)
if [ "$rc" -eq 0 ] && [ "$before" = "$after" ] && printf '%s' "$report" | jq -e '
    .status == "findings" and .scanned_files == 2
    and (.findings | length) == 9
    and [.findings[].severity] == ["high","high","high","medium","medium","medium","low","low","low"]
    and ([.findings[].rule] | sort) == ["broken-local-link","broken-local-link","broken-local-link","deleted-path-reference","malformed-verification-stamp","missing-anchor","missing-anchor","stale-verification-stamp","stale-verification-stamp"]
    and ([.findings[] | select(.target == "docs/not-created.md" or .target == "docs/tilde-missing.md" or .target == "docs/indented-missing.md")] | length) == 0
    and all(.findings[]; keys == ["detail","file","line","rule","severity","target"])' >/dev/null; then
    pass "scanner is read-only and reports stable local-link/anchor/history/stamp findings"
else
    fail "scanner findings, false-positive suppression, or read-only contract drifted"
    printf '%s\n' "$report"
fi

for bad_now in 2026-00 2026-13; do
    if DOC_GARDEN_NOW="$bad_now" bash "$WORK/repo/scripts/harness/lib/doc-garden.sh" --repo "$WORK/repo" --format json >/dev/null 2>&1; then
        fail "invalid current month $bad_now was accepted"
    else
        pass "invalid current month $bad_now is rejected"
    fi
done

mkdir "$WORK/findings-is-a-directory"
if DOC_GARDEN_FINDINGS_FILE="$WORK/findings-is-a-directory" \
    bash "$WORK/repo/scripts/harness/lib/doc-garden.sh" --repo "$WORK/repo" --format json >/dev/null 2>&1; then
    fail "finding-record initialization failure was swallowed"
else
    pass "finding-record failure is fatal"
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails doc-garden test(s)"; exit 1; fi
echo "OK: doc-garden tests passed"
