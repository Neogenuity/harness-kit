#!/usr/bin/env bash
# The executable definition of "done": the ordered quality gates every task
# must pass before it is complete. AGENTS.md, CLAUDE.md, and the skills all
# point HERE instead of listing commands, so the gates can never disagree
# across files — edit this file, never the docs.
#
#   bash scripts/verify.sh          # run every gate, in order, fail-fast
#   bash scripts/verify.sh --fast   # fast gates only (formatter, linter) —
#                                   # cheap enough for an agent stop-hook
#
# Keep gates ordered cheapest-first so failures surface early. A failing gate
# prints the command's output plus the exact command to re-run, then stops.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

MODE=full
case "${1:-}" in
    "") ;;
    --fast) MODE=fast ;;
    *)
        echo "usage: bash scripts/verify.sh [--fast]" >&2
        exit 64
        ;;
esac

# gate <label> <command...>       — runs in both modes; keep these fast (ms-s).
# full_gate <label> <command...>  — skipped under --fast (typecheck, tests).
# Commands run verbatim ("$@"); wrap pipelines in `bash -c '...'`.
run_gate() {
    local label="$1" out; shift
    if out=$("$@" 2>&1); then
        echo "ok:   $label"
    else
        printf '%s\n' "$out"
        echo "FAIL: $label — fix, then re-run: $*"
        exit 1
    fi
}
gate() { run_gate "$@"; }
full_gate() { [ "$MODE" = "fast" ] && return 0; run_gate "$@"; }

# -- TAILOR: the ordered quality gates -----------------------------------------
# Fill these from the project's real toolchain at init. Examples:
#
# gate      "format"    vendor/bin/pint --test
# gate      "lint"      npx oxlint
# full_gate "typecheck" vendor/bin/phpstan analyse --no-progress
# full_gate "tests"     php artisan test --parallel

full_gate "harness" bash scripts/check-harness.sh
# ------------------------------------------------------------------------------

echo "OK: all quality gates passed ($MODE)"
exit 0
