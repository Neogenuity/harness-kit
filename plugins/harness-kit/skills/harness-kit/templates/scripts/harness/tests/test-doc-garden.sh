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

# A second fixture keeps the GFM-slug and deleted-set behaviors readable and
# leaves the broad findings assertion above undisturbed.
mkdir -p "$WORK/gfm/scripts/harness/lib" "$WORK/gfm/docs"
cp "$SCRIPTS_DIR/doc-garden.sh" "$WORK/gfm/scripts/harness/lib/doc-garden.sh"
git -C "$WORK/gfm" init -q
git -C "$WORK/gfm" config user.email test@example.invalid
git -C "$WORK/gfm" config user.name Test
printf '# A\n' > "$WORK/gfm/docs/gone-a.md"
printf '# B\n' > "$WORK/gfm/docs/gone-b.md"
printf '# Back\n' > "$WORK/gfm/docs/back.md"
# A backtick is legal in a POSIX path and printable ASCII, so git reports it
# unquoted — and such a path is invisible to a backtick split. It must still be
# found via the longer code-span delimiter CommonMark requires for it.
printf '# Tick\n' > "$WORK/gfm/docs/tick\`name.md"
# Unreferenced bulk deletions: they add no findings, but they are what the
# ls-files invocation count below measures the scan's shape against.
for _i in c d e f g h i j k l; do printf '# %s\n' "$_i" > "$WORK/gfm/docs/gone-$_i.md"; done
git -C "$WORK/gfm" add docs
git -C "$WORK/gfm" commit -qm seed
git -C "$WORK/gfm" rm -q -r docs
git -C "$WORK/gfm" commit -qm delete
mkdir -p "$WORK/gfm/docs"
# Recreated after deletion: still in --diff-filter=D history, not actionable.
printf '# Back\n' > "$WORK/gfm/docs/back.md"
# GitHub drops ":" and the symbol but hyphenates EACH surviving space, so the
# real anchor carries a double hyphen. A trailing space must not add one.
{
    printf '# Provider Portability: DigitalOcean \342\206\224 AWS\n\n'
    printf '## Trailing Space Heading  \n\n'
    printf '## Two  Spaces Inside\n'
} > "$WORK/gfm/docs/api.md"
{
    printf '# GFM\n\n'
    printf '[real double hyphen](docs/api.md#provider-portability-digitalocean--aws)\n'
    printf '[collapsed run is not the anchor](docs/api.md#provider-portability-digitalocean-aws)\n'
    printf '[trailing space trimmed](docs/api.md#trailing-space-heading)\n'
    printf '[interior run](docs/api.md#two--spaces-inside)\n\n'
    printf 'Two on one line: `docs/gone-a.md` and `docs/gone-b.md`.\n'
    printf 'Adjacent spans: `docs/gone-a.md`text`docs/gone-b.md`\n'
    printf 'Repeat on one line: `docs/gone-a.md` then `docs/gone-a.md` again.\n'
    printf 'Recreated `docs/back.md` is not actionable.\n'
    printf 'Backtick path: ``docs/tick`name.md`` stays findable.\n'
} > "$WORK/gfm/README.md"
git -C "$WORK/gfm" add README.md docs/api.md docs/back.md
git -C "$WORK/gfm" commit -qm docs

gfm_report=$(DOC_GARDEN_NOW=2026-07 bash "$WORK/gfm/scripts/harness/lib/doc-garden.sh" \
    --repo "$WORK/gfm" --format json)
if printf '%s' "$gfm_report" | jq -e '
    ([.findings[] | select(.rule == "missing-anchor") | .target]
        == ["provider-portability-digitalocean-aws"])' >/dev/null; then
    pass "GFM slugging hyphenates each space, so double-hyphen anchors resolve"
else
    fail "GFM anchor slugging drifted (double-hyphen anchors or the trailing-space trim)"
    printf '%s\n' "$gfm_report"
fi

# One scan per file over the whole deleted set must still report every
# (line, path) pair exactly once, and must still skip recreated paths.
if printf '%s' "$gfm_report" | jq -e '
    ([.findings[] | select(.rule == "deleted-path-reference")
        | .line, .target] | tostring)
      == ([[8,"docs/gone-a.md"],[8,"docs/gone-b.md"],
           [9,"docs/gone-a.md"],[9,"docs/gone-b.md"],
           [10,"docs/gone-a.md"],
           [12,"docs/tick`name.md"]] | flatten | tostring)' >/dev/null; then
    pass "deleted-set scan reports each (line, path) once and skips recreated paths"
else
    fail "deleted-path-reference set scan drifted (dedupe, multi-target lines, or recreate filter)"
    printf '%s' "$gfm_report" | jq -c '[.findings[] | select(.rule == "deleted-path-reference")]'
fi

# The set scan's contract is that per-file work does not scale with the number
# of historically deleted paths. Pin that shape structurally rather than by
# wall clock: the pairwise form re-listed the tracked Markdown set once per
# deleted path (12 actionable deletions here => 13 listings), so any regression
# back to it shows up as an invocation count that tracks Git history.
# `type -P`, not `command -v`: the latter would also answer for a function or
# builtin, and an empty resolution here used to produce a shim whose body was
# `exec  "$@"` — the counting case then reported a PERFORMANCE REGRESSION for a
# fixture that was never built. Resolve first, and skip if it cannot be.
_real_git=$(type -P -- git 2>/dev/null) || _real_git=""
mkdir -p "$WORK/shim"
{
    printf '#!/usr/bin/env bash\n'
    printf 'case " $* " in *" ls-files "*) echo x >> %s ;; esac\n' "$WORK/ls-files-calls"
    printf 'exec "%s" "$@"\n' "$_real_git"
} > "$WORK/shim/git"
# 755, not `chmod +x`: the latter is masked by the caller's umask.
chmod 755 "$WORK/shim/git"
: > "$WORK/ls-files-calls"
PATH="$WORK/shim:$PATH" DOC_GARDEN_NOW=2026-07 \
    bash "$WORK/gfm/scripts/harness/lib/doc-garden.sh" --repo "$WORK/gfm" --format json >/dev/null
_ls_calls=$(awk 'END {print NR}' "$WORK/ls-files-calls")
if [ -n "$_real_git" ] && [ "$_ls_calls" -le 4 ]; then
    pass "deleted-path scan does not re-walk the file set per deleted path ($_ls_calls ls-files calls)"
else
    fail "deleted-path scan re-walks the tracked Markdown set per deleted path ($_ls_calls ls-files calls, expected <= 4)"
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails doc-garden test(s)"; exit 1; fi
echo "OK: doc-garden tests passed"
