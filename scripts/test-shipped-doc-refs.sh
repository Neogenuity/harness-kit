#!/usr/bin/env bash
# test-shipped-doc-refs.sh — documentation must not cite a script that isn't there.
#
# Two passes, because this repo rots in two different ways:
#
# 1. SHIPPED prose (templates + the skill's mode references) describes an
#    INSTALLED repo, so a `scripts/...` path it names must exist under
#    templates/scripts/. Motivating regressions: v0.22.0 descoped test-eval.sh
#    to maintainer-only but left seven references promising it as active
#    enforcement (issue #13) — including AGENTS.md.tmpl, which writes the claim
#    into every adopting repo's index; and v0.23.0 left coverage gates pointing
#    at retired paths. The failure is silent by construction: the kit repo HAS
#    the script at root, so every check that looks at THIS tree passes.
#
# 2. THIS repo's own agent-facing prose (AGENTS.md, .harness/) must cite paths
#    that actually exist at the root. Same rot, other direction — the
#    restructure-migration-miss class, where installed copies keep the old name
#    after a rename. It bit during the issue-#13 fix itself, which corrected
#    seven shipped references while leaving three phantom
#    `scripts/harness/tests/test-eval.sh` citations sitting in .harness/.
#
# A citation is OK when the path exists, or is declared in the kit-manifest as
# a shipped/authored layer — `optional-policy` (scripts/dev.sh: authored per
# repo, never copied, and absent from a library repo like this one) and
# `content` are cited legitimately even though no copy is shipped. Anything
# else — a `retired` path, or one that exists nowhere — is the defect.
#
# Boundary, stated as plainly as check #8's "detects drift, does not prove
# equivalence": this greps prose for script-shaped tokens and proves the cited
# path RESOLVES. It does not prove the surrounding claim is true. Declare a
# deliberate exception (a hypothetical example, a maintainer-only script) with
# `doc-ref-ok: <path>` on any line of a scanned file.
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

# Extract cited ROOT-RELATIVE script paths from the named files.
#
# Two failure modes to thread between, both found in review:
#   * matching a bare `scripts/` anywhere invents phantom top-level paths out of
#     deeper ones (.harness/context-efficiency-eval/scripts/run-cell2.sh became
#     a "missing" scripts/run-cell2.sh);
#   * requiring a non-path character before `scripts/` silently DROPS the common
#     root-prefixed forms `./scripts/x.sh` and `$ROOT/scripts/x.sh` — 9 real
#     citations, including $ROOT/scripts/harness/lib/provider-lib.sh, went
#     unchecked, so the gate would have stayed green if they were renamed.
#
# So: grab the whole path-ish token, strip the root prefixes that still mean
# "repo root" ("$VAR"/, $VAR/, ./), and keep only what then begins with
# `scripts/`. A token with a real directory prefix left over points into another
# tree and is out of scope.
extract_refs() {
    grep -hoE '[A-Za-z0-9_./$"-]*scripts/[A-Za-z0-9_./-]+\.sh' "$@" 2>/dev/null \
        | sed -e 's|^"*||' \
              -e 's|^\$[A-Za-z_][A-Za-z0-9_]*"*/||' \
              -e 's|^\./||' \
        | grep '^scripts/' | sort -u
}

# Declared in the ship contract as shipped or authored-per-repo.
declared_in_manifest() {
    [ -f "$MANIFEST" ] || return 1
    awk -v p="$1" '$1 ~ /^(mechanism|policy|optional-policy|content)$/ && $2 == p {found=1} END {exit !found}' "$MANIFEST"
}

[ -d "$TMPL/scripts" ] || { echo "SKIP: no shipped scripts tree at $TMPL/scripts"; exit 0; }

# --- pass 1: shipped prose, resolved against templates/ ---------------------
shipped_files=$(find "$TMPL/docs" "$SKILL/references" "$TMPL/scripts/harness/lib" \
                     "$TMPL/scripts/harness/hooks" -type f 2>/dev/null)
[ -f "$TMPL/AGENTS.md.tmpl" ] && shipped_files="$shipped_files
$TMPL/AGENTS.md.tmpl"

schecked=0
while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    schecked=$((schecked + 1))
    [ -f "$TMPL/$ref" ] && continue
    declared_in_manifest "$ref" && continue
    if printf '%s\n' "$shipped_files" | tr '\n' '\0' | xargs -0 grep -qF "doc-ref-ok: $ref" 2>/dev/null; then
        ok "$ref — declared exception (doc-ref-ok)"
        continue
    fi
    note=""
    if [ -f "$MANIFEST" ] && awk -v p="$ref" '$1=="retired" && $2==p {found=1} END {exit !found}' "$MANIFEST"; then
        note=" (kit-manifest marks it 'retired' — the kit no longer ships it)"
    fi
    where=$(printf '%s\n' "$shipped_files" | tr '\n' '\0' | xargs -0 grep -lF "$ref" 2>/dev/null | tr '\n' ' ')
    bad "shipped docs cite '$ref' but the kit ships no such script$note — adopters get the doc, not the mechanism. Cited by: ${where:-?}. Point at a shipped path, restate the claim as an authoring requirement, or declare it with 'doc-ref-ok: $ref'"
done <<EOF
$(printf '%s\n' "$shipped_files" | while IFS= read -r f; do [ -n "$f" ] && extract_refs "$f"; done | sort -u)
EOF

# --- pass 2: this repo's own prose, resolved against the root ---------------
# Tracked files only: .harness/var/ is gitignored runtime scratch (eval
# transcripts quoting old command lines), not documentation.
local_files=$(git ls-files 'AGENTS.md' '.harness/**/*.md' '.harness/**/*.sh' 2>/dev/null)
lchecked=0
if [ -n "$local_files" ]; then
    while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        lchecked=$((lchecked + 1))
        [ -f "$ref" ] && continue
        declared_in_manifest "$ref" && continue
        if printf '%s\n' "$local_files" | tr '\n' '\0' | xargs -0 grep -qF "doc-ref-ok: $ref" 2>/dev/null; then
            continue
        fi
        lwhere=$(printf '%s\n' "$local_files" | tr '\n' '\0' | xargs -0 grep -lF "$ref" 2>/dev/null | tr '\n' ' ')
        bad "this repo's own docs cite '$ref' but no such file exists — a rename or relocation left the citation behind. Cited by: ${lwhere:-?}"
    done <<EOF
$(printf '%s\n' "$local_files" | while IFS= read -r f; do [ -n "$f" ] && extract_refs "$f"; done | sort -u)
EOF
fi

[ "$fails" -eq 0 ] && ok "$schecked shipped + $lchecked local cited script path(s) all resolve"

echo "----"
if [ "$fails" -eq 0 ]; then echo "test-shipped-doc-refs: all checks passed"; exit 0; fi
echo "test-shipped-doc-refs: $fails check(s) failed"; exit 1
