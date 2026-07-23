#!/usr/bin/env bash
# Root-only dogfood gate: never shipped in the plugin templates (no shipped
# entry in the kit-manifest ship contract), pinned as '# tailored' in
# scripts/harness/.harness-manifest by the release step, not by this script. Validates
# that the REAL shipped provider hook configs in
# plugins/harness-kit/skills/harness-kit/templates/providers/{claude,cursor,codex}
# pass check-harness.sh check #8d (the frozen hook-tuple contract) inside a
# throwaway install fixture — not synthetic configs, the actual bytes this kit
# ships. This is the positive half of the old template test-install.sh's
# "real shipped provider hook configs" case (see git history around
# test-install.sh:513-538), split out into its own root-only gate.
set -uo pipefail

# Recursion guard. This fixture installs the mechanism and runs its
# check-harness.sh, whose check #6 runs every scripts/test-*.sh copied into
# the fixture — including nested copies of test-install.sh and
# test-check-harness.sh, each of which would spin up its own sub-fixture and
# recurse forever without this. Seeing HARNESS_NESTED_FIXTURE already set on
# entry means we ARE such a nested run, so exit cleanly.
if [ -n "${HARNESS_NESTED_FIXTURE:-}" ]; then
    echo "ok:   test-provider-templates.sh skipped (HARNESS_NESTED_FIXTURE set — nested run)"
    exit 0
fi
export HARNESS_NESTED_FIXTURE=1

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL_SCRIPTS="$ROOT/plugins/harness-kit/skills/harness-kit/templates/scripts"
TPL_PROVIDERS="$ROOT/plugins/harness-kit/skills/harness-kit/templates/providers"
[ -d "$TPL_PROVIDERS" ] || { echo "SKIP: no provider templates"; exit 0; }

# shellcheck source=/dev/null
. "$TPL_SCRIPTS/harness/lib/install-lib.sh"
KIT_VERSION="0.0.0-fixture"

# Guarded scratch base — bare `mktemp -d` ignores $TMPDIR on macOS (it
# resolves _CS_DARWIN_USER_TEMP_DIR instead) and fails outright in a sandbox;
# an unguarded failure leaves the path EMPTY, and bash `cd ""` is a silent
# rc=0 no-op, so a later `git commit` would land in the HOST repo. The
# fixture below carves its directory out of this already-guarded base.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-provider-templates.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { echo "ok:   $1"; }
fail() { echo "FAIL: $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; fails=$((fails + 1)); }
git_c() { git -c user.email=t@example.com -c user.name=t "$@"; }

# --- real shipped provider hook configs validate against the frozen contract ---
F=$(mktemp -d "$WORK/providers.XXXXXX") || exit 1
( cd "${F:?}" && git init -q )
harness_install_mechanism "$TPL_SCRIPTS" "$F"
harness_append_gitignore "$F"
{ grep -vE '^(HOOK_WIRED_PROVIDERS|AGENT_PROVIDERS|EXECUTION_PROFILE_PROVIDERS)=' "$F/scripts/harness/harness.conf"
  printf 'HOOK_WIRED_PROVIDERS=".claude .cursor .codex"\nAGENT_PROVIDERS=""\nEXECUTION_PROFILE_PROVIDERS=""\n'
} > "$F/scripts/hc" && mv "$F/scripts/hc" "$F/scripts/harness/harness.conf"
mkdir -p "$F/.claude" "$F/.cursor" "$F/.codex"
cp "$TPL_PROVIDERS/claude/settings.json" "$F/.claude/settings.json"
cp "$TPL_PROVIDERS/cursor/hooks.json" "$F/.cursor/hooks.json"
cp "$TPL_PROVIDERS/codex/hooks.json" "$F/.codex/hooks.json"
harness_generate_manifest "$F" "$KIT_VERSION" > "$F/scripts/harness/.harness-manifest"
( cd "${F:?}" && git_c add -A && git_c commit -qm init >/dev/null )
out=$(cd "${F:?}" && bash scripts/harness/check-harness 2>&1); rc=$?
if [ "$rc" = "0" ]; then
    pass "real templates: shipped provider hook configs validate all tuples (#8d)"
else
    fail "real templates: shipped hook configs failed check-harness" "$out"
fi
rm -rf "$F"

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails provider-template case(s)"
    exit 1
fi
echo "PASSED: all provider-template cases"
exit 0
