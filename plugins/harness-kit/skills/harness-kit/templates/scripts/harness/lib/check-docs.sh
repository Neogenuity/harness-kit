#!/usr/bin/env bash
# check-docs.sh — the "docs" family of harness coherence checks, split from
# the pre-v0.23.0 check-harness.sh monolith (block numbering retained for
# continuity). Standalone entry: scripts/harness/check-docs. The check-harness
# orchestrator runs every family and owns the combined summary.
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "$0")/check-common.sh"

# 4. Relative markdown links in the knowledge base must resolve — AGENTS.md
#    (root and nested, per the hierarchical standard) and every doc under
#    docs/. A dead link strands every agent. Fenced code blocks are ignored;
#    a link passes if it resolves from the doc's own directory OR the repo
#    root (both conventions are common).
check_doc_links() {
    local doc="$1" doc_rel base link target
    doc_rel=${doc#"$ROOT"/}
    base=$(dirname "$doc")
    while IFS= read -r link; do
        [ -z "$link" ] && continue
        case "$link" in
            http://*|https://*|mailto:*|\#*) continue ;;
        esac
        target="${link%%#*}"
        # Strip an optional link title and unwrap an <angle-bracketed>
        # destination so the existence test sees the path alone:
        #   [t](dest "title")  [t](dest 'title')  [t](dest (title))  [t](<dest>)
        # Per CommonMark a bare destination ends at the first space; an
        # angle-bracketed one ends at '>' and may itself contain spaces.
        target="${target#"${target%%[![:space:]]*}"}"   # trim leading space
        case "$target" in
            "<"*) target="${target#<}"; target="${target%%>*}" ;;
            *)    target="${target%% *}" ;;
        esac
        [ -z "$target" ] && continue
        if [ ! -e "$base/$target" ] && [ ! -e "$ROOT/$target" ]; then
            echo "ERROR: $doc_rel links to '$target' but it does not exist"
            ERRORS=$((ERRORS + 1))
        fi
    done < <(awk '/^```/ { fence = !fence; next } !fence' "$doc" 2>/dev/null \
        | grep -oE '\]\([^)]+\)' | sed -E 's/^\]\(//; s/\)$//' | sort -u)
}
while IFS= read -r doc; do
    check_doc_links "$doc"
done < <({ find "$ROOT" -name AGENTS.md \
             -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*'; \
           [ -d "$ROOT/docs" ] && find "$ROOT/docs" -name '*.md'; } 2>/dev/null | sort -u)


# 10c. Doctor: keep a verification-stamped reference (e.g. a provider/capability
#      matrix) fresh. Watches PROVIDER_MATRIX_DOC (default
#      references/provider-matrix.md; absent in most repos, so a no-op there).
#      Stamps are self-dating text ("verified YYYY-MM" or "YYYY-MM-DD"), so —
#      unlike the plan check — this needs no git history and works in shallow
#      CI. WARNs on a stamp older than the configured age, and on a doc that has
#      tables but carries no stamp at all.
MATRIX_DOC="${PROVIDER_MATRIX_DOC:-references/provider-matrix.md}"
MATRIX_STALE_DAYS="${HARNESS_MATRIX_STALE_DAYS:-90}"
if [ -f "$ROOT/$MATRIX_DOC" ]; then
    _thresh=$(date -d "-${MATRIX_STALE_DAYS} days" +%F 2>/dev/null \
        || date -v-"${MATRIX_STALE_DAYS}"d +%F 2>/dev/null || true)
    _stamps=$(grep -oE 'verified [0-9]{4}-[0-9]{2}(-[0-9]{2})?' "$ROOT/$MATRIX_DOC" \
        | sed -E 's/^verified //' | sort -u)
    if [ -z "$_stamps" ] && grep -qE '^\|.*\|' "$ROOT/$MATRIX_DOC"; then
        echo "WARNING: $MATRIX_DOC has tables but no 'verified <date>' stamps — its facts carry no freshness marker"
    fi
    if [ -n "$_thresh" ]; then
        while IFS= read -r _s; do
            [ -n "$_s" ] || continue
            case "$_s" in ????-??) _cmp="${_s}-01" ;; *) _cmp="$_s" ;; esac
            if [[ "$_cmp" < "$_thresh" ]]; then
                echo "WARNING: $MATRIX_DOC has a 'verified $_s' stamp older than $MATRIX_STALE_DAYS days — re-verify those facts against their primary docs and restamp"
            fi
        done <<< "$_stamps"
    fi
fi


check_trailer "docs"
