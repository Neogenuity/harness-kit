#!/usr/bin/env bash
# Agent hook (before file edit/write): deny agent edits to the files that
# define the harness itself — hook scripts, the sync/check/verify machinery,
# the manifest, hook wiring, CI gates — plus (TAILOR) the linter/formatter
# configs. An agent that can edit the guard can silence it; "fix the code,
# not the lint config" must be mechanical, not aspirational.
#
# Scope: defense-in-depth, not a boundary — shell edits (`sed -i` via Bash)
# are not intercepted; scripts/check-harness.sh's manifest verification is
# the enforcing layer in CI. Intentional harness maintenance is the escape
# hatch: run the session with HARNESS_ALLOW_MECHANISM_EDITS=1 (or edit by
# hand), then re-pin scripts/.harness-manifest. Fails open on unknown
# payloads.
set -uo pipefail

. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

[ "${HARNESS_ALLOW_MECHANISM_EDITS:-0}" = "1" ] && exit 0

hook_read_input
file=$(hook_file_path)
[ -n "$file" ] || exit 0

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
rel="${file#"$ROOT"/}"

# -- TAILOR: paths agents may not edit -----------------------------------------
# Repo-relative globs. Patterns without a slash also match by basename (so
# nested lint configs are covered). The harness mechanism is protected by
# default; uncomment/extend the second list with the lint and formatter
# configs an agent could edit to make findings disappear.
PROTECTED_PATHS="
scripts/hooks/*.sh
scripts/check-harness.sh
scripts/sync-agent-skills.sh
scripts/test-*.sh
scripts/.harness-manifest
.claude/settings.json
.cursor/hooks.json
.codex/hooks.json
.opencode/plugins/*
opencode.json
.github/workflows/harness-check.yml
"
# PROTECTED_PATHS="$PROTECTED_PATHS .eslintrc* eslint.config.* biome.json ruff.toml pint.json .php-cs-fixer.php phpstan.neon"
# ------------------------------------------------------------------------------

# Globs must reach `case` verbatim; without noglob the unquoted expansion of
# PROTECTED_PATHS would glob against the CWD.
set -f

base=$(basename "$rel")
# $pat is deliberately unquoted in the case patterns below: the protected
# list is globs, and case-glob matching is the point.
for pat in $PROTECTED_PATHS; do
    hit=0
    # shellcheck disable=SC2254
    case "$rel" in $pat) hit=1 ;; esac
    # shellcheck disable=SC2254
    case "$pat" in
        */*) ;;
        *) case "$base" in $pat) hit=1 ;; esac ;;
    esac
    if [ "$hit" = "1" ]; then
        hook_deny "Blocked by scripts/hooks/guard-config.sh: '$rel' is harness mechanism or a protected config. If a check is failing, fix the code it complains about — do not edit the check. Intentional harness maintenance: re-run with HARNESS_ALLOW_MECHANISM_EDITS=1, then re-pin scripts/.harness-manifest (see check-harness.sh)."
    fi
done

exit 0
