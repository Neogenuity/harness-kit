#!/usr/bin/env bash
# test-shipped-doc-refs.sh — no shipped doc cites a script the kit does not ship.
#
# Adopter-facing prose (the templates and the skill's mode references) describes
# an INSTALLED repo, so a `scripts/...` path it names must exist under
# templates/scripts/. Two live regressions motivated this gate:
#
#   * v0.22.0 descoped test-eval.sh to maintainer-only but left seven
#     references promising it as active enforcement (issue #13) — including
#     AGENTS.md.tmpl, which writes the claim into every adopting repo's
#     canonical index;
#   * v0.23.0 left coverage gates pointing at retired paths.
#
# Both shipped a documented mechanism adopters never received, and no gate saw
# it. The failure is silent by construction: the kit repo HAS the script at
# root, so every check that looks at the repo passes.
#
# Boundary, stated as plainly as check #8's "detects drift, does not prove
# equivalence": this greps prose for script-shaped tokens and proves the cited
# path is SHIPPED. It does not prove the surrounding claim is true. Declare a
# A cited path is OK when it either exists under templates/scripts/ or is
# declared in the kit-manifest as a shipped/authored layer — `optional-policy`
# (scripts/dev.sh: authored per repo, never copied) and `content` are cited
# legitimately even though the kit ships no copy. Anything else — a `retired`
# path, or one that exists nowhere — is the defect. Declare a deliberate
# exception (a hypothetical example, a maintainer-only script) with
# `doc-ref-ok: <path>` on any line of a scanned file: one comment, so this
# never wedges an author who has a real reason.
#
# Root-only and tailored: it reasons about this repo's plugin layout.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

SKILL="plugins/harness-kit/skills/harness-kit"
TMPL="$SKILL/templates"
MANIFEST="$TMPL/scripts/harness/kit-manifest"

fails=0
ok()  { printf 'ok:   %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1"; fails=$((fails + 1)); }

[ -d "$TMPL/scripts" ] || { echo "SKIP: no shipped scripts tree at $TMPL/scripts"; exit 0; }

# Prose an adopter reads as describing THEIR repo: the shipped docs, the AGENTS
# index template, the skill's mode references, and the header comments of the
# shipped library and hook scripts.
scan_roots="$TMPL/docs $SKILL/references $TMPL/scripts/harness/lib $TMPL/scripts/harness/hooks"
[ -f "$TMPL/AGENTS.md.tmpl" ] && scan_roots="$scan_roots $TMPL/AGENTS.md.tmpl"

# shellcheck disable=SC2086  # deliberate word-split of the root list
cited=$(grep -rhoE '`?scripts/[A-Za-z0-9_./-]+\.sh`?' $scan_roots 2>/dev/null \
        | tr -d '`' | sort -u)

checked=0
while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    checked=$((checked + 1))

    [ -f "$TMPL/$ref" ] && continue

    # Declared in the ship contract as shipped or authored-per-repo.
    if [ -f "$MANIFEST" ] && awk -v p="$ref" \
            '$1 ~ /^(mechanism|policy|optional-policy|content)$/ && $2 == p {found=1} END {exit !found}' \
            "$MANIFEST"; then
        continue
    fi

    # An explicit, declared exception anywhere in the scanned prose.
    # shellcheck disable=SC2086
    if grep -rqF "doc-ref-ok: $ref" $scan_roots 2>/dev/null; then
        ok "$ref — declared exception (doc-ref-ok)"
        continue
    fi

    # A `retired` kit-manifest line is the unambiguous case: it WAS shipped.
    note=""
    if [ -f "$MANIFEST" ] \
            && awk -v p="$ref" '$1=="retired" && $2==p {found=1} END {exit !found}' "$MANIFEST"; then
        note=" (kit-manifest marks it 'retired' — the kit no longer ships it)"
    fi

    # Name the citing files, so the fix is one grep away.
    # shellcheck disable=SC2086
    where=$(grep -rlF "$ref" $scan_roots 2>/dev/null | tr '\n' ' ')
    bad "shipped docs cite '$ref' but the kit ships no such script$note — adopters get the doc, not the mechanism. Cited by: ${where:-?}. Point at a shipped path, restate the claim as an authoring requirement, or declare it with 'doc-ref-ok: $ref'"
done <<EOF
$cited
EOF

[ "$fails" -eq 0 ] && ok "all $checked cited script path(s) are shipped"

echo "----"
if [ "$fails" -eq 0 ]; then echo "test-shipped-doc-refs: all checks passed"; exit 0; fi
echo "test-shipped-doc-refs: $fails check(s) failed"; exit 1
