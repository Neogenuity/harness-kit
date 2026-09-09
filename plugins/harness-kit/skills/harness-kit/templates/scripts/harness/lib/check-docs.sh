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
# The knowledge-base doc set whose links must resolve. AGENTS.md (root and
# nested), the root entry pages, and the committed .harness/ + .agents/skills/
# zones live outside docs/ but are part of the same link web — a dead link in
# any of them strands an agent just the same; llms.txt uses markdown link
# syntax too. NOT scanned: provider stub dirs (.claude/, .cursor/, ... —
# generated, pinned by sync --check) and the kit's own plugin templates/ +
# references/, whose relative links resolve from the post-install location (and
# whose _example/_template files carry intentional placeholder targets), so
# scanning the source templates would false-positive.

# _harness_glob_escape <string> — quote the fnmatch metacharacters find's
# -path honors (\ [ ] * ?) so a literal string embeds in a -path pattern as
# itself. Load-bearing twice over: $ROOT is whatever directory this checkout
# happens to live in, and a component like 'app[1]' or 'v*' is legal on every
# filesystem this runs on; and a NESTED_CHECKOUT_PATHS entry is documented as a
# literal directory path, not a glob — escaping it is what keeps a stray '*'
# in an adopter's config from pruning the entire repository.
_harness_glob_escape() {
    local _s="$1"
    _s=${_s//\\/\\\\}
    _s=${_s//\[/\\[}
    _s=${_s//\]/\\]}
    _s=${_s//\*/\\*}
    _s=${_s//\?/\\?}
    printf '%s' "$_s"
}

# DOC_PRUNE — the OR-ed `-path` fragment naming every subtree the AGENTS.md
# scan below must not walk. A plain indexed array, assembled element by
# element so no quoting survives into find's argv: bash 3.2 is the floor here
# (no associative arrays, no mapfile, no ${var,,}).
DOC_PRUNE=()
_doc_prune_add() {
    if [ "${#DOC_PRUNE[@]}" -gt 0 ]; then DOC_PRUNE+=(-o); fi
    DOC_PRUNE+=(-path "$1")
}
_doc_prune_root=$(_harness_glob_escape "$ROOT")
# Built-ins, pruned at ANY depth. The two-pattern form ("$R/x" plus "$R/*/x",
# where find's fnmatch '*' spans '/') keeps the any-depth reach of a bare
# '*/x' while anchoring every pattern under $ROOT — so no pattern can match
# the start directory itself and prune the whole scan away. That is not
# hypothetical: against a bare '*/vendor', a checkout whose own directory is
# named 'vendor' prunes at depth 0 and the check silently examines nothing.
for _doc_prune_name in .git node_modules vendor .claude/worktrees; do
    _doc_prune_add "$_doc_prune_root/$_doc_prune_name"
    _doc_prune_add "$_doc_prune_root/*/$_doc_prune_name"
done
# NESTED_CHECKOUT_PATHS (harness.conf) — the project-declared extension of the
# same idea: foreign or nested checkouts outside this repository's
# documentation graph (a metarepo's child clones, a second worktree set, a
# vendored sibling repo). ROOT-ANCHORED, unlike the built-ins: 'repos' prunes
# $ROOT/repos and nothing else, so the repo's own packages/repos/ stays in the
# doc set. Anchoring is also what makes "no entry can ever prune $ROOT"
# structural rather than a validation promise: every pattern is "$ROOT/" plus
# at least one more character, and the only path find emits equal to $ROOT is
# the start directory, which carries no such suffix. The validation below is
# therefore not that guarantee — it is what makes a bad entry LOUD instead of
# a silent no-op ($ROOT/../x matches nothing and would otherwise pass
# unremarked). It WARNs and skips, never ERRORs: an adopter's config typo must
# not turn this gate red for a reason that has nothing to do with their docs.
set -f   # entries must reach the validator verbatim; see guard-secrets.sh
for _doc_prune_entry in ${NESTED_CHECKOUT_PATHS:-}; do
    _doc_prune_e="$_doc_prune_entry"
    # Absolute paths are not repo-relative. Checked before the trailing-slash
    # trim so a bare "/" is rejected here rather than as an empty string.
    case "$_doc_prune_e" in /*) _doc_prune_e="" ;; esac
    # "repos/" == "repos"; the loop also collapses "repos///".
    while [ -n "$_doc_prune_e" ] && [ "$_doc_prune_e" != "${_doc_prune_e%/}" ]; do
        _doc_prune_e="${_doc_prune_e%/}"
    done
    # Reject the empty string and any '.' or '..' path segment. One rule
    # covers ".", "..", "../x", "x/..", "repos/../.." — everything that names
    # $ROOT itself or a path outside it — plus "./repos", the spelling that
    # looks right and prunes nothing ($ROOT/./repos never matches a path find
    # prints).
    case "/$_doc_prune_e/" in //|*/./*|*/../*) _doc_prune_e="" ;; esac
    if [ -z "$_doc_prune_e" ]; then
        echo "WARNING: NESTED_CHECKOUT_PATHS entry '$_doc_prune_entry' (harness.conf) is not a usable repo-relative directory path — it must be relative to the repo root and carry no '.' or '..' segment. Ignoring it: nothing is pruned for this entry, so any docs under it are still link-checked"
        continue
    fi
    _doc_prune_add "$_doc_prune_root/$(_harness_glob_escape "$_doc_prune_e")"
done
set +f

_harness_doc_set() {
    local _f
    # .claude/worktrees/ is pruned for the same reason the formatter-ignore
    # block excludes it: it holds FULL nested checkouts of this repo (Claude
    # Code's worktree feature), hidden from Git via .git/info/exclude, which
    # nothing outside Git reads. Without the prune this find returns one
    # AGENTS.md per live worktree, so a broken link in a branch someone else
    # is still writing fails THIS checkout's gate, naming a path the reader
    # is not editing and cannot fix from here. -prune, not another -not -path:
    # -not -path only suppresses the RESULT, leaving find to walk every file of
    # every live worktree first, so the cost of the scan would still multiply
    # by the worktree count. That reasoning applies unchanged to .git/,
    # node_modules/ and vendor/ — result filters historically, real prune
    # branches now — and to every path a project declares in
    # NESTED_CHECKOUT_PATHS. DOC_PRUNE above is the assembled expression.
    # The other doc producers below are already safe: they either name a file
    # explicitly or start from a .harness/ subtree.
    find "$ROOT" \( "${DOC_PRUNE[@]}" \) -prune -o \
        -name AGENTS.md -print 2>/dev/null
    for _f in ARCHITECTURE.md README.md SECURITY.md CONTRIBUTING.md GEMINI.md llms.txt; do
        [ -f "$ROOT/$_f" ] && printf '%s\n' "$ROOT/$_f"
    done
    [ -d "$ROOT/.harness/policies" ] && find "$ROOT/.harness/policies" "$ROOT/.harness/agents" -name '*.md' 2>/dev/null
    [ -d "$ROOT/.harness/evals" ] && find "$ROOT/.harness/evals" -name '*.md' 2>/dev/null
    [ -d "$ROOT/.agents/skills" ] && find "$ROOT/.agents/skills" -name '*.md' 2>/dev/null
    [ -d "$ROOT/docs" ] && find "$ROOT/docs" -name '*.md' 2>/dev/null
    return 0
}
while IFS= read -r doc; do
    check_doc_links "$doc"
done < <(_harness_doc_set | sort -u)


# 4b. Machine contracts under .harness/schemas/ must at least be valid JSON —
#     a schema that no longer parses silently stops describing anything, and
#     nothing else executes these files. Deliberately shallow (jq empty, no
#     instance validation): the schemas are documentation-grade contracts, and
#     a fake deep gate would claim verification this repo doesn't run.
#     jq-gated like the other JSON checks; no jq, no claim.
if command -v jq >/dev/null 2>&1 && [ -d "$ROOT/.harness/schemas" ]; then
    for _schema in "$ROOT"/.harness/schemas/*.json; do
        [ -f "$_schema" ] || continue
        if ! jq empty "$_schema" >/dev/null 2>&1; then
            echo "ERROR: ${_schema#"$ROOT"/} is not valid JSON — a machine contract that cannot parse describes nothing; fix or remove it"
            ERRORS=$((ERRORS + 1))
        fi
    done
fi


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
        # Process substitution + a consumption counter rather than a
        # here-string: see assert_loop_ran in check-common.sh.
        _stamps_read=0
        while IFS= read -r _s; do
            _stamps_read=$((_stamps_read + 1))
            [ -n "$_s" ] || continue
            case "$_s" in ????-??) _cmp="${_s}-01" ;; *) _cmp="$_s" ;; esac
            if [[ "$_cmp" < "$_thresh" ]]; then
                echo "WARNING: $MATRIX_DOC has a 'verified $_s' stamp older than $MATRIX_STALE_DAYS days — re-verify those facts against their primary docs and restamp"
            fi
        done < <(printf '%s\n' "$_stamps")
        assert_loop_ran "$_stamps_read" "verification-stamp freshness check #10c for $MATRIX_DOC"
    fi
fi


check_trailer "docs"
