#!/usr/bin/env bash
# Agent hook (session start): print a short situational-awareness banner —
# current branch, working-tree state, and the active execution plans — so a
# fresh session (including subagents and worktrees) starts oriented without
# having to think to look.
#
# Provider-agnostic banner output: plain text on stdout, and no stdin
# dependency unless CLAUDE_ENV_FILE is set. When Claude Code supplies a
# SessionStart payload plus CLAUDE_ENV_FILE, persist the exact session/provider
# into its documented per-session Bash environment so later verify runs are
# attributable without a shared state file — that is the ONLY branch that reads
# stdin. Other providers ignore it and use their own environment adapters.
# Fails open — missing jq/git, an unwritable env file, or an empty plans
# directory just shrinks the behavior.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT" || exit 0

# shellcheck source=/dev/null
[ -f "$ROOT/scripts/harness/harness.conf" ] && . "$ROOT/scripts/harness/harness.conf" 2>/dev/null
PLANS_DIR="${PLANS_DIR:-docs/plans/active}"

# Read stdin ONLY on the Claude branch that consumes it. `cat` on a pipe that
# is open but never closed blocks forever, so every other provider — and a
# bare manual invocation inside a `while read` loop — must keep the hook's
# original stdin-free contract rather than pay a hang risk for a payload it
# never uses.
if [ -n "${CLAUDE_ENV_FILE:-}" ] && command -v jq >/dev/null 2>&1 && [ ! -t 0 ]; then
    payload=$(cat 2>/dev/null || true)
    session_id=$(printf '%s' "$payload" | jq -r '
        .session_id // empty
        | select(type == "string" and length > 0 and length <= 256)
        | select(test("^[A-Za-z0-9._/-]+$"))' 2>/dev/null)
    if [ -n "$session_id" ]; then
        # SessionStart has no matcher, so it fires on startup, resume, clear,
        # and compact, and this file is sourced into every later Bash call.
        # Replace our own two lines instead of appending: a plain `>>` grows
        # without bound and leaves a previous session's id above the current
        # one, making attribution depend on last-write-wins ordering.
        env_tmp="$CLAUDE_ENV_FILE.harness.$$"
        if : > "$env_tmp" 2>/dev/null; then
            if [ -e "$CLAUDE_ENV_FILE" ]; then
                grep -v -e '^export HARNESS_SESSION_ID=' -e '^export HARNESS_PROVIDER=' \
                    "$CLAUDE_ENV_FILE" >> "$env_tmp" 2>/dev/null || true
            fi
            if {
                printf "export HARNESS_SESSION_ID='%s'\n" "$session_id"
                printf "export HARNESS_PROVIDER='claude'\n"
            } >> "$env_tmp" 2>/dev/null; then
                mv -f "$env_tmp" "$CLAUDE_ENV_FILE" 2>/dev/null || rm -f "$env_tmp" 2>/dev/null || true
            else
                rm -f "$env_tmp" 2>/dev/null || true
            fi
        fi
    fi
fi

if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null)
    [ -n "$branch" ] || branch="(detached HEAD)"
    dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d '[:space:]')
    if [ "${dirty:-0}" = "0" ]; then
        state="clean"
    else
        state="$dirty uncommitted change(s)"
    fi
    echo "Branch: $branch ($state)"
    # Recent-commits block: OFF by default (BANNER_RECENT_COMMITS=0). The
    # context-efficiency audit found no in-session consumer across 60+
    # transcripts, and it costs ~70 tokens on every session and every subagent.
    # Set BANNER_RECENT_COMMITS=N in harness.conf to include the last N commits.
    n="${BANNER_RECENT_COMMITS:-0}"
    if [ "$n" -gt 0 ] 2>/dev/null; then
        recent=$(git log --oneline -"$n" 2>/dev/null)
        [ -n "$recent" ] && printf 'Recent commits:\n%s\n' "$recent"
    fi
fi

if [ -d "$PLANS_DIR" ]; then
    # paste with a single-char delimiter (BSD paste alternates multi-char lists)
    plans=$(find "$PLANS_DIR" -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null \
        | sed 's|.*/||; s|\.md$||' | sort | paste -sd ',' - | sed 's/,/, /g')
    [ -n "$plans" ] && echo "Active plans ($PLANS_DIR/): $plans"
fi

exit 0
