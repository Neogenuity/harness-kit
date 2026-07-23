#!/usr/bin/env bash
# provider-lib.sh — derive the per-facet provider sets from a single
# HARNESS_PROVIDERS declaration + the kit-owned capability table
# (scripts/harness/lib/provider-caps). SOURCED by check-common.sh (so every
# check family sees the same derived sets) and by sync-lib.sh; never run
# standalone. Pure bash 3.2 + awk, no jq (ADR 002; ADR 011).
#
# The caller sets PROVIDER_CAPS_FILE to the table's absolute path before
# sourcing; the sibling file next to this lib is the fallback. Membership of
# each derived list = HARNESS_PROVIDERS filtered by the facet's capability
# column; the wiring facts (which file, which dialect, native reader or not)
# are kit knowledge and live only in the table.

# _provider_caps_file — the table path (explicit override, else this lib's
# sibling). Kept as a function so the fallback resolves at call time, not
# source time (BASH_SOURCE is this lib regardless of the caller's $0).
_provider_caps_file() {
    if [ -n "${PROVIDER_CAPS_FILE:-}" ] && [ -f "$PROVIDER_CAPS_FILE" ]; then
        printf '%s' "$PROVIDER_CAPS_FILE"; return 0
    fi
    printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/provider-caps"
}

# harness_caps_field <provider> <col> — the column value (2..5) for a provider
# row; exit 1 (empty output) when the provider has no row. Columns: 2
# skill_stubs, 3 agent_dialect, 4 hook_config, 5 exec_config.
harness_caps_field() {
    local want="$1" col="$2" f; f=$(_provider_caps_file)
    [ -f "$f" ] || return 1
    awk -v p="$want" -v c="$col" '
        /^[[:space:]]*#/ { next }
        NF == 0 { next }
        $1 == p { print $c; found = 1; exit }
        END { exit !found }' "$f"
}

# harness_caps_providers — every provider dir named in the table (the
# validation universe: a HARNESS_PROVIDERS entry outside it is "unknown"),
# one per line.
harness_caps_providers() {
    local f; f=$(_provider_caps_file); [ -f "$f" ] || return 1
    awk '/^[[:space:]]*#/ { next } NF == 0 { next } { print $1 }' "$f"
}

# harness_derive_providers <facet> — HARNESS_PROVIDERS filtered by capability.
#   skill  → skill_stubs == yes
#   agent  → agent_dialect != none (and present)
#   hook   → hook_config   != none (and present)
# Prints the surviving providers space-separated (no leading/trailing space).
# An entry absent from the table contributes to no facet (the declaration
# validator in check-instructions.sh turns that into a loud ERROR).
harness_derive_providers() {
    local facet="$1" p val out=""
    for p in ${HARNESS_PROVIDERS:-}; do
        case "$facet" in
            skill) val=$(harness_caps_field "$p" 2) || val=""
                   [ "$val" = "yes" ] && out="$out $p" ;;
            agent) val=$(harness_caps_field "$p" 3) || val=""
                   [ -n "$val" ] && [ "$val" != "none" ] && out="$out $p" ;;
            hook)  val=$(harness_caps_field "$p" 4) || val=""
                   [ -n "$val" ] && [ "$val" != "none" ] && out="$out $p" ;;
        esac
    done
    printf '%s' "${out# }"
}

# harness_resolve_set <VARNAME> <facet> — the override-or-derive resolution
# that preserves declared-not-inferred:
#   1. VARNAME already set (explicit harness.conf override) → leave it;
#   2. else HARNESS_PROVIDERS set → assign the derived set (may be empty);
#   3. else leave VARNAME UNSET → the caller's "declare the set" diagnostic
#      still fires (a legacy pre-declaration install carries neither variable,
#      since harness.conf is diff-only on update).
# Never infers from directory presence — derivation reads only the explicit
# HARNESS_PROVIDERS declaration and the kit's static table.
harness_resolve_set() {
    local var="$1" facet="$2" derived
    eval "[ -n \"\${$var+x}\" ]" && return 0
    [ -n "${HARNESS_PROVIDERS+x}" ] || return 0
    # shellcheck disable=SC2034  # consumed by the eval assignment below
    derived=$(harness_derive_providers "$facet")
    eval "$var=\$derived"
}
