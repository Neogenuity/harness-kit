#!/usr/bin/env bash
# check-common.sh — shared preamble for the check-family scripts
# (check-instructions.sh, check-docs.sh, check-plan.sh, check-tests.sh,
# check-drift.sh, check-doctor.sh). SOURCED by each family after its own
# `set -uo pipefail`; never run standalone. Families run standalone (their
# own trailer + exit) or under the check-harness orchestrator
# (HARNESS_CHECK_CHILD=1 suppresses the trailer; the orchestrator sums
# ERROR lines and owns the combined summary).
ERRORS=0
# families live in scripts/harness/lib/ — three levels below the repo root
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# shellcheck source=/dev/null
[ -f "$ROOT/scripts/harness/harness.conf" ] && . "$ROOT/scripts/harness/harness.conf"

# Derive the per-facet wiring sets from the single HARNESS_PROVIDERS
# declaration + the kit-owned capability table (ADR 011). An explicit
# harness.conf value for any set wins (the override knob); otherwise it is
# derived; otherwise it stays unset so the family's "declare the set"
# diagnostic still fires. provider-lib.sh is mechanism shipped alongside this
# file — guard on its presence so a partial/legacy tree degrades to the old
# defaults rather than erroring.
# shellcheck disable=SC2034  # read by provider-lib.sh across the source boundary
PROVIDER_CAPS_FILE="$ROOT/scripts/harness/lib/provider-caps"
# shellcheck source=/dev/null
[ -f "$ROOT/scripts/harness/lib/provider-lib.sh" ] && . "$ROOT/scripts/harness/lib/provider-lib.sh"
if command -v harness_resolve_set >/dev/null 2>&1; then
    harness_resolve_set PROVIDERS skill
    harness_resolve_set AGENT_PROVIDERS agent
    harness_resolve_set HOOK_WIRED_PROVIDERS hook
fi
PROVIDERS="${PROVIDERS:-.claude .cursor .opencode}"
CANONICAL_SKILLS="${CANONICAL_SKILLS:-.agents/skills}"

sha256_of() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    fi
}
# consumed by the drift family (shellcheck can't see across the source)
# shellcheck disable=SC2034
MANIFEST="$ROOT/scripts/harness/.harness-manifest"

# assert_loop_ran <lines-read> <what> — the shared "this check actually ran"
# guard for every `while read` in this family, and the reason those loops are
# fed by process substitution rather than a here-doc.
#
# Bash backs a HERE-DOC with a temp file — bash 3.2 writes it under $TMPDIR and
# falls back to the CWD. With neither writable the redirection fails, and under
# `set -uo pipefail` without `set -e` a failed redirection skips the entire
# compound command. A loop that is a check's only error source therefore leaves
# the script printing "OK: <family> checks passed" for a repo it never examined:
# a check that could not run is indistinguishable from a clean one. That is
# github.com/Neogenuity/harness-kit/issues/15, first fixed for the drift family
# in v0.34.0 and then reproduced live in two adopter repos — one of them losing
# the #8d hook-wiring validator, which is the check that proves the guards are
# wired at all.
#
# Process substitution needs no temp file; this counter is what proves the loop
# consumed its input. Callers must feed `printf '%s\n' "$var"` — never a bare
# pipeline, which can legitimately produce zero lines. `printf` always emits at
# least one line (byte-identical to the here-doc it replaces), so an empty set
# still yields one skipped read and a zero count means only "the input never
# arrived".
#
# A loop that `break`s or `return`s early must NOT be converted: the writer
# would take an EPIPE under an inherited-ignored SIGPIPE, the phantom-failure
# mode this repo hit live twice (v0.16.0 macOS, v0.20.0 ubuntu). Those sites
# stay on here-docs and say so at the loop.
assert_loop_ran() {
    [ "${1:-0}" -gt 0 ] && return 0
    echo "ERROR: $2 did not run — the shell could not deliver the loop its input, so this check's silence is not a pass. Re-run; if it persists, the temp/file-descriptor state that redirections depend on is broken"
    ERRORS=$((ERRORS + 1))
    return 1
}

# check_trailer <family-label> — standalone trailer; suppressed under the
# orchestrator, which owns the combined count.
check_trailer() {
    if [ -n "${HARNESS_CHECK_CHILD:-}" ]; then
        [ "$ERRORS" -gt 0 ] && exit 1
        exit 0
    fi
    if [ "$ERRORS" -gt 0 ]; then
        echo ""
        echo "FAILED: $ERRORS $1 check(s)"
        exit 1
    fi
    echo "OK: $1 checks passed"
    exit 0
}
