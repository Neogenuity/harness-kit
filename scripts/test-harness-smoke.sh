#!/usr/bin/env bash
# Post-init / post-update smoke test — the one install-mechanics check that
# SHIPS to adopters (the kit's exhaustive install/update/recovery and checker
# conformance suites are maintainer-only since v0.22.0). It answers the only
# question an adopter needs answered after an install or upgrade: does THIS
# repo's installed mechanism, installed fresh into a throwaway fixture,
# produce a harness whose own checker comes back green?
#
# Self-contained on purpose: it sources only the shipped install-lib.sh (no
# test library), owns its scratch fixture, and runs with no model in the
# loop. Runnable standalone and picked up by check-harness.sh check #6 and
# verify.sh's test glob by its scripts/test-*.sh name.
set -uo pipefail

# Recursion guard: this test installs the mechanism into a fixture and runs
# the fixture's check-harness.sh, whose check #6 runs every scripts/test-*.sh
# — including the fixture's copy of THIS file. Seeing HARNESS_NESTED_FIXTURE
# already set means we ARE that nested copy: exit before building a fixture
# inside the fixture.
if [ -n "${HARNESS_NESTED_FIXTURE:-}" ]; then
    echo "ok:   $(basename "$0") skipped (HARNESS_NESTED_FIXTURE set — nested run)"
    exit 0
fi
export HARNESS_NESTED_FIXTURE=1

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPTS_DIR/install-lib.sh"

# Guarded mktemp: bare `mktemp -d` ignores $TMPDIR on macOS and fails outright
# in a sandbox; an unguarded failure leaves the path empty and `cd ""` is a
# silent no-op that would put fixture operations in the HOST repo (see
# check #5b and docs/plans/completed/v0.18.0-fixture-isolation.md).
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-harness-smoke.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

W="$WORK/fixture"
mkdir -p "${W:?}"
( cd "${W:?}" && git init -q ) 2>/dev/null || true

harness_install_mechanism "$SCRIPTS_DIR" "$W" \
    || { echo "FAIL: harness-smoke — harness_install_mechanism failed (no kit-manifest in ${SCRIPTS_DIR}?)"; exit 1; }
harness_append_gitignore "$W"

# This is a bare mechanism fixture: no provider configs, agent personas, or
# MCP inventories are authored (that is the model-graded half of init), so
# reset the declarations the semantic checks would otherwise judge this
# repo's real providers against. Robust to a conf that never had the lines.
{ grep -vE '^(HOOK_WIRED_PROVIDERS|AGENT_PROVIDERS|EXECUTION_PROFILE_PROVIDERS|MCP_ALLOWED_SERVERS)=' "$W/scripts/harness.conf"
  printf 'HOOK_WIRED_PROVIDERS=""\nAGENT_PROVIDERS=""\nEXECUTION_PROFILE_PROVIDERS=""\n'
} > "$W/scripts/harness.conf.tmp" && mv "$W/scripts/harness.conf.tmp" "$W/scripts/harness.conf"

harness_generate_manifest "$W" "0.0.0-smoke" > "$W/scripts/.harness-manifest" \
    || { echo "FAIL: harness-smoke — harness_generate_manifest failed"; exit 1; }

out=$(bash "$W/scripts/check-harness.sh" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASSED: harness smoke (fresh fixture install, checker green)"
else
    echo "FAIL: harness-smoke — the fixture's check-harness.sh exited $rc:"
    printf '%s\n' "$out" | tail -20 | sed 's/^/        /'
    exit 1
fi
