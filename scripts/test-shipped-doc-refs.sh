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
# GLOB citations count too. Prose names a whole family far more often than a
# single file — "each scripts/harness/tests/test-*.sh passes standalone" — and
# the original token regex stopped dead at `*`, extracting nothing at all. That
# blind spot outlived the v0.23.0 tests/ relocation inside references/modes/
# init.md, which went on telling adopters to run `scripts/harness/hooks/
# test-*.sh` from a directory that has held no tests since. A glob resolves
# when it matches at least one shipped file; an empty match is the same defect
# as a missing literal, because the family it promises is not there.
#
# Boundary, stated as plainly as check #8's "detects drift, does not prove
# equivalence": this proves a cited path RESOLVES. It does not prove the
# surrounding CLAIM is true — prose can point at a live path and still describe
# it wrongly, and two of the defects fixed alongside this extension did exactly
# that. Two mechanical extensions for the claim class were prototyped against
# this tree and REJECTED on measured noise, not taste:
#
#   * flagging prose that names a RETIRED script by basename matched ~30 live
#     files, because v0.23.0 MOVED scripts rather than deleting them, so nearly
#     every retired basename is also a current one (retired scripts/audit-log.sh
#     vs shipped scripts/harness/lib/audit-log.sh);
#   * flagging an edit-verb near a mechanism-declared path matched only
#     legitimate "edit the canonical doc, then run <mechanism>" phrasings, and
#     missed the real defect, whose sentence said "that script" — an anaphor
#     carrying no path token.
#
# A stale claim about a path that still resolves is a review-layer concern. Do
# not bolt on a heuristic that fires on the shape of a sentence rather than the
# existence of a file.
#
# Declare a deliberate exception (a hypothetical example, a maintainer-only
# script) with `doc-ref-ok: <path>` on any line of a scanned file.
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
# "repo root" ("$VAR"/, $VAR/, ${VAR}/, ./), and keep only what then begins with
# `scripts/`. A token with a real directory prefix left over points into another
# tree and is out of scope.
_ref_tokens() {
    grep -hoE '[A-Za-z0-9_./${}"-]*scripts/[A-Za-z0-9_./*?-]+\.sh' "$@" 2>/dev/null \
        | sed -e 's|^"*||' \
              -e 's|^\${[A-Za-z_][A-Za-z0-9_]*}"*/||' \
              -e 's|^\$[A-Za-z_][A-Za-z0-9_]*"*/||' \
              -e 's|^\./||' \
        | grep '^scripts/'
}

# LITERALS come from the whole file, code included: a stale
# `. "$ROOT/scripts/harness/lib/x.sh"` is a real dependency break, which is why
# the root-prefixed forms are handled at all.
#
# GLOBS come from prose only — every line of a .md/.tmpl/.conf, but only COMMENT
# lines of a .sh. In shell code a glob is a loop domain that is ALLOWED to be
# empty by design (`for h in "$ROOT"/scripts/*.sh; do [ -f "$h" ] || continue`),
# so demanding that it match would flag a correct idiom, and the only way to
# silence it would be doc-ref-ok annotations pushed into SHIPPED mechanism
# comments to satisfy a maintainer-only root gate. In a comment or a doc, the
# same token is a promise about a family that either exists or does not.
extract_refs() {
    local f
    for f in "$@"; do
        _ref_tokens "$f" | grep -v '[*?]'
        case "$f" in
            *.sh) grep -hE '^[[:space:]]*#' "$f" 2>/dev/null | _ref_tokens - ;;
            *)    _ref_tokens "$f" ;;
        esac | grep '[*?]'
    done | sort -u
}

# Does a citation point at something real? A literal must be a file; a glob must
# match at least one — an empty family is the same broken promise as a missing
# file. `compgen -G` is the one builtin that answers "does this pattern match
# anything" without leaving an unexpanded literal behind on no-match.
ref_resolves() {
    local m
    # The glob branch expands $1 UNQUOTED on purpose: that expansion IS the
    # test. With no match bash leaves the pattern literal and [ -f ] then fails,
    # which is the answer we want. `-f` (not `-e`) so a DIRECTORY named
    # test-x.sh cannot satisfy a citation the literal branch would reject.
    # shellcheck disable=SC2086
    case "$1" in
        *[*?]*) for m in $1; do [ -f "$m" ] && return 0; done; return 1 ;;
        *)      [ -f "$1" ] ;;
    esac
}

# Wording for the failure message, so a glob does not get reported as a file.
ref_noun() {
    case "$1" in
        *[*?]*) echo "no file matching that pattern" ;;
        *)      echo "no such script" ;;
    esac
}

# Declared in the ship contract as shipped or authored-per-repo.
declared_in_manifest() {
    [ -f "$MANIFEST" ] || return 1
    awk -v p="$1" '$1 ~ /^(mechanism|policy|optional-policy|content)$/ && $2 == p {found=1} END {exit !found}' "$MANIFEST"
}

[ -d "$TMPL/scripts" ] || { echo "SKIP: no shipped scripts tree at $TMPL/scripts"; exit 0; }

# --- pass 1: shipped prose, resolved against templates/ ---------------------
# The shipped runner/config surface carries adopter-facing prose too, and went
# unscanned until the gates.conf defect above: an installed gates.conf inherits
# every stale sentence in the template verbatim. kit-manifest is excluded on
# purpose — its `retired` lines name dead paths BY DESIGN, which is the whole
# point of the file. So is scripts/harness/tests/, whose fixtures cite
# deliberately fake paths (evil.sh, X.sh) as test payloads.
shipped_files=$(find "$TMPL/docs" "$SKILL/references" "$TMPL/scripts/harness/lib" \
                     "$TMPL/scripts/harness/hooks" -type f 2>/dev/null
                find "$TMPL/scripts/harness" -maxdepth 1 -type f \
                     ! -name kit-manifest 2>/dev/null)
for extra in "$TMPL/AGENTS.md.tmpl" "$TMPL/scripts/gates.conf" "$SKILL/SKILL.md"; do
    [ -f "$extra" ] && shipped_files="$shipped_files
$extra"
done

schecked=0
while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    schecked=$((schecked + 1))
    ref_resolves "$TMPL/$ref" && continue
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
    bad "shipped docs cite '$ref' but the kit ships $(ref_noun "$ref")$note — adopters get the doc, not the mechanism. Cited by: ${where:-?}. Point at a shipped path, restate the claim as an authoring requirement, or declare it with 'doc-ref-ok: $ref'"
done < <(printf '%s\n' "$shipped_files" | while IFS= read -r f; do [ -n "$f" ] && extract_refs "$f"; done | sort -u)

# A here-doc fed these loops until v0.35.0. That is the issue-#15 fail-open
# class: bash 3.2 puts the here-doc temp in $TMPDIR and falls back to CWD, so
# from an unwritable directory the loop body never ran, the counters stayed 0,
# and the gate still exited 0 — green while checking nothing. Process
# substitution removes the temp file entirely (neither loop breaks early, so
# there is no SIGPIPE hazard), and the counter assertion below is the backstop
# that makes any future silent-skip loud.
if [ "$schecked" -eq 0 ]; then
    bad "pass 1 extracted ZERO citations from $(printf '%s\n' "$shipped_files" | grep -c .) shipped files — the scan did not run. Treat a green result as invalid until this is explained (issue-#15 fail-open class)"
fi

# --- pass 2: this repo's own prose, resolved against the root ---------------
# Tracked files only: .harness/var/ is gitignored runtime scratch (eval
# transcripts quoting old command lines), not documentation.
local_files=$(git ls-files 'AGENTS.md' '.harness/gates.conf' '.harness/**/*.md' '.harness/**/*.sh' 2>/dev/null)
lchecked=0
if [ -n "$local_files" ]; then
    while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        lchecked=$((lchecked + 1))
        ref_resolves "$ref" && continue
        declared_in_manifest "$ref" && continue
        if printf '%s\n' "$local_files" | tr '\n' '\0' | xargs -0 grep -qF "doc-ref-ok: $ref" 2>/dev/null; then
            continue
        fi
        lwhere=$(printf '%s\n' "$local_files" | tr '\n' '\0' | xargs -0 grep -lF "$ref" 2>/dev/null | tr '\n' ' ')
        bad "this repo's own docs cite '$ref' but $(ref_noun "$ref") exists here — a rename or relocation left the citation behind. Cited by: ${lwhere:-?}"
    done < <(printf '%s\n' "$local_files" | while IFS= read -r f; do [ -n "$f" ] && extract_refs "$f"; done | sort -u)
    if [ "$lchecked" -eq 0 ]; then
        bad "pass 2 extracted ZERO citations from this repo's own tracked prose — the scan did not run (issue-#15 fail-open class)"
    fi
else
    # No git, or nothing tracked at these paths. Legitimate outside a checkout,
    # but say so: a silent "0 local" reads as a clean result when it is really
    # an unrun check.
    echo "note: pass 2 skipped — git listed no tracked AGENTS.md/.harness prose here"
fi

[ "$fails" -eq 0 ] && ok "$schecked shipped + $lchecked local cited script path(s) all resolve"

echo "----"
if [ "$fails" -eq 0 ]; then echo "test-shipped-doc-refs: all checks passed"; exit 0; fi
echo "test-shipped-doc-refs: $fails check(s) failed"; exit 1
