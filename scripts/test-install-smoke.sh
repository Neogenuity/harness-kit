#!/usr/bin/env bash
# Post-init / post-update smoke test — this is a MAINTAINER-ONLY
# install-mechanics smoke (descoped from the shipped floor — adopters'
# install proof is now check-drift + the guard hook + the shipped hook
# behavioral tests). It installs the SHIPPED artifact (templates/scripts)
# into a throwaway fixture and asserts the fixture's checker is green.
#
# Self-contained on purpose: it sources only the shipped install-lib.sh (no
# test library), owns its scratch fixture, and runs with no model in the
# loop. Runnable standalone and picked up by verify's install-suite-smoke
# gate (.harness/gates.conf) by its scripts/test-*.sh name.
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

SCRIPTS_DIR="$(cd "$(dirname "$0")/../plugins/harness-kit/skills/harness-kit/templates/scripts" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPTS_DIR/harness/lib/install-lib.sh"

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
# repo's real providers against. HARNESS_PROVIDERS is neutralized to "" so the
# derived wiring sets — and the generated adapters — validate zero providers.
# Robust to a conf that never had the lines.
{ grep -vE '^(HARNESS_PROVIDERS|HOOK_WIRED_PROVIDERS|AGENT_PROVIDERS|EXECUTION_PROFILE_PROVIDERS|MCP_ALLOWED_SERVERS)=' "$W/scripts/harness/harness.conf"
  printf 'HARNESS_PROVIDERS=""\nHOOK_WIRED_PROVIDERS=""\nAGENT_PROVIDERS=""\nEXECUTION_PROFILE_PROVIDERS=""\n'
} > "$W/scripts/harness/harness.conf.tmp" && mv "$W/scripts/harness/harness.conf.tmp" "$W/scripts/harness/harness.conf"

harness_generate_manifest "$W" "0.0.0-smoke" > "$W/scripts/harness/.harness-manifest" \
    || { echo "FAIL: harness-smoke — harness_generate_manifest failed"; exit 1; }

out=$(bash "$W/scripts/harness/check-harness" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASSED: harness smoke (fresh fixture install, checker green)"
else
    echo "FAIL: harness-smoke — the fixture's check-harness.sh exited $rc:"
    printf '%s\n' "$out" | tail -20 | sed 's/^/        /'
    exit 1
fi
