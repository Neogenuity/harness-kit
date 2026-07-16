#!/usr/bin/env bash
# Regression test for the generated Codex hook wiring (providers/codex/
# hooks.json): every hook command must resolve its script path from the Git
# root, so a Codex session whose CWD is a repository subdirectory still finds
# the hook. Codex runs hooks with the session CWD, so a relative
# `bash scripts/hooks/X.sh` exits 127 from a subdir — reproduced in the PR #6
# review. The shipped wiring resolves from the Git root and fails open when
# there is no Git worktree, per the hooks docs
# (https://learn.chatgpt.com/docs/hooks, verified 2026-07-10).
#
# Runs byte-identically in both contexts by locating the wiring wherever it
# lives: installed as scripts/hooks/test-*.sh (wiring at <root>/.codex/
# hooks.json) or shipped as templates/scripts/hooks/test-*.sh (wiring at
# <templates>/providers/codex/hooks.json).
set -uo pipefail

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not available"; exit 0; }

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HOOKS_DIR/../.." && pwd)"
WIRING=""
for cand in "$BASE/.codex/hooks.json" "$BASE/providers/codex/hooks.json"; do
    [ -f "$cand" ] && { WIRING="$cand"; break; }
done
[ -n "$WIRING" ] || { echo "SKIP: no Codex hooks.json found near $HOOKS_DIR"; exit 0; }

fails=0
checked=0

# Throwaway repo whose scripts/hooks/ holds the real hook scripts, so a
# Git-root-resolved command can locate and execute them from a nested CWD.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/test-codex-hooks-cwd.XXXXXX") || exit 1; trap 'rm -rf "$WORK"' EXIT
git -C "$WORK" init -q
mkdir -p "$WORK/scripts/hooks" "$WORK/deep/nested/dir"
cp "$HOOKS_DIR"/*.sh "$WORK/scripts/hooks/"

# Each command must (a) carry the Git-root resolver and (b) actually run from a
# nested CWD without a 127 "command/script not found".
while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    checked=$((checked + 1))
    case "$cmd" in
        *'git rev-parse --show-toplevel'*) ;;
        *) echo "FAIL: command is not Git-root-resolved: $cmd"; fails=$((fails + 1)); continue ;;
    esac
    ( cd "$WORK/deep/nested/dir" && printf '' | eval "$cmd" ) >/dev/null 2>&1
    rc=$?
    if [ "$rc" = "127" ]; then
        echo "FAIL: exited 127 (script not found) from a nested CWD: $cmd"
        fails=$((fails + 1))
    else
        echo "ok:   resolves + runs from a nested CWD (exit $rc): ${cmd#bash }"
    fi
done < <(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$WIRING")

# A vacuous pass is a failure: if the jq query yields nothing (a reshaped or
# malformed hooks.json), the loop never runs and the test would otherwise
# print PASSED having verified nothing.
[ "$checked" -gt 0 ] || { echo "FAIL: jq extracted no hook commands from $WIRING"; fails=$((fails + 1)); }

# Fail-open outside a Git worktree: root discovery fails, so the command must
# exit 0 rather than run bash on an empty root (which would 127). Pins the
# PR #6 Codex-review fix; a plain `bash "$(git rev-parse …)/…"` would 127 here.
if [ "$checked" -gt 0 ]; then
    NOGIT=$(mktemp -d "${TMPDIR:-/tmp}/test-codex-hooks-cwd-nogit.XXXXXX") || exit 1
    firstcmd=$(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$WIRING" | head -n 1)
    # $TMPDIR itself may sit inside a Git worktree (a CI scratch dir, an agent
    # sandbox, a ~/tmp kept in dotfiles) — then discovery from NOGIT finds THAT
    # repo, so this case would silently test a repo-rooted CWD and assert
    # nothing. Cap the upward walk. The ceiling must be NOGIT's PARENT, not
    # NOGIT: discovery starts at the CWD and only consults the list when
    # ascending, so a ceiling of NOGIT itself is never reached.
    nogit_parent=$(dirname "$NOGIT")
    ( cd "$NOGIT" && export GIT_CEILING_DIRECTORIES="$nogit_parent" \
        && printf '' | eval "$firstcmd" ) >/dev/null 2>&1
    rc=$?
    rm -rf "$NOGIT"
    if [ "$rc" = "0" ]; then
        echo "ok:   fails open (exit 0) outside a Git worktree"
    else
        echo "FAIL: outside a Git worktree expected fail-open exit 0, got $rc"
        fails=$((fails + 1))
    fi
fi

if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails Codex hook-command case(s)"
    exit 1
fi
echo "PASSED: all Codex hook commands resolve from the Git root ($checked commands)"
