#!/usr/bin/env bash
# Drift gate for the dogfood installation (THIS repo only — never shipped).
# The templates under plugins/harness-kit/skills/harness-kit/templates/scripts/ are the
# source of truth; the root scripts/ are the kit's own installed copy (see
# docs/architecture/decisions/006-dogfood-copies-are-enforced-duplicates.md).
# Every non-tailored mechanism file must be byte-identical to its template
# twin — otherwise this repo dogfoods a stale mechanism while shipping a
# newer one, and CI stays green on the lie.
#
# Named test-*.sh on purpose (historically for the checker's #6 glob); since
# v0.23.0 it runs as this repo's explicit `template-sync` gate in
# .harness/gates.conf, and harness.conf's GUARD_PROTECTED_EXTRA protects it,
# with zero edits to any shipped mechanism.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/plugins/harness-kit/skills/harness-kit/templates/scripts"
MANIFEST="$ROOT/scripts/harness/.harness-manifest"

[ -d "$TPL" ] || { echo "SKIP: no template dir at ${TPL#"$ROOT"/}"; exit 0; }

fails=0
checked=0

# kit-manifest src= overrides: a template file whose installed home differs
# from the default `scripts/<template-rel>` derivation (e.g. gates.conf
# installs to .harness/gates.conf). Read once from the SHIPPED kit-manifest —
# the same contract install/update derive from, so this suite can never
# disagree with them about where a template lands.
SRC_MAP=$(awk '$1 !~ /^#/ {
    for (i = 3; i <= NF; i++) if ($i ~ /^src=/) { sub(/^src=/, "", $i); print $i, $2 }
}' "$TPL/harness/kit-manifest" 2>/dev/null)

# installed_rel <template-rel> — where this template installs in a repo.
installed_rel() {
    local trel="$1" line
    while IFS= read -r line; do
        [ "${line%% *}" = "$trel" ] && { printf '%s' "${line#* }"; return; }
    done <<EOF
$SRC_MAP
EOF
    printf 'scripts/%s' "$trel"
}

# template_rel <installed-rel> — the template twin for an installed path.
template_rel() {
    local rel="$1" line
    while IFS= read -r line; do
        [ "${line#* }" = "$rel" ] && { printf '%s' "${line%% *}"; return; }
    done <<EOF
$SRC_MAP
EOF
    printf '%s' "${rel#scripts/}"
}

# Exemptions: harness.conf is policy (tailored per repo by design), and any
# manifest line ending '# tailored' marks a deliberate local fork that is
# allowed — expected, even — to diverge from its template.
is_exempt() {
    local rel="$1"
    [ "$rel" = "scripts/harness/harness.conf" ] && return 0
    grep -qE "[[:space:]]${rel} # tailored$" "$MANIFEST" 2>/dev/null
}

# Forward: every shipped mechanism template must have a byte-identical
# installed twin at the repo root.
while IFS= read -r tpl_file; do
    rel=$(installed_rel "${tpl_file#"$TPL"/}")
    is_exempt "$rel" && continue
    checked=$((checked + 1))
    if [ ! -f "$ROOT/$rel" ]; then
        echo "FAIL: $rel is missing but its template ships — install it:"
    elif ! cmp -s "$tpl_file" "$ROOT/$rel"; then
        echo "FAIL: $rel does not match its template (templates are the source of truth) — roll it forward:"
    else
        continue
    fi
    fix="cp ${tpl_file#"$ROOT"/} $rel"
    case "$rel" in *.sh) fix="$fix && chmod +x $rel" ;; esac
    echo "        $fix"
    echo "        then re-pin its line in scripts/harness/.harness-manifest: shasum -a 256 $rel"
    fails=$((fails + 1))
done < <(find "$TPL" -type f | sort)

# Reverse: every non-tailored file the manifest pins must still have a
# template twin — a template rename/removal must not leave a stale installed
# copy behind.
while IFS= read -r line; do
    case "$line" in \#*|"") continue ;; *"# tailored"*) continue ;; esac
    rel=$(printf '%s\n' "$line" | awk '{print $2}')
    [ -n "$rel" ] || continue
    if [ ! -f "$TPL/$(template_rel "$rel")" ]; then
        echo "FAIL: $rel is manifest-pinned but has no template twin under plugins/harness-kit/skills/harness-kit/templates/scripts/ — the template was renamed or removed; update the installed copy and its manifest line to match"
        fails=$((fails + 1))
    fi
done < "$MANIFEST"

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails template-sync issue(s)"
    exit 1
fi
echo "PASSED: installed mechanism matches templates ($checked files)"
