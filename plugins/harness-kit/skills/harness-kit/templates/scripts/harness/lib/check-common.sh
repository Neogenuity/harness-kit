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
