#!/usr/bin/env bash
# Agent hook (before file edit/write): deny agent edits to the files that
# define the harness itself — hook scripts, the sync/check/verify machinery,
# the manifest, hook wiring, CI gates, harness.conf, the Claude Code local
# settings override, the per-provider MCP / execution-profile configs, and an
# adopted devcontainer boundary — plus (TAILOR) the linter/formatter configs.
# An agent that can edit the guard can silence it;
# "fix the code, not the lint config" must be mechanical, not aspirational.
#
# Provider-agnostic via lib.sh:hook_affected_files — Cursor/Claude Code file
# paths and Codex apply_patch envelopes (every file in a multi-file patch is
# checked). General shell commands are deliberately NOT scanned: read vs
# write is indistinguishable from command text (a scan would deny
# `git checkout scripts/hooks/lib.sh` and every mention of a protected
# path), so shell edits (`sed -i` via Bash) are not intercepted;
# scripts/check-harness.sh's manifest verification is the enforcing layer in
# CI. Intentional harness maintenance is the escape hatch: run the session
# with HARNESS_ALLOW_MECHANISM_EDITS=1 (or edit by hand), then re-pin
# scripts/.harness-manifest — the same ceremony covers post-init harness.conf
# tailoring (new SECRET_PATTERNS, MCP_ALLOWED_SERVERS entries, etc.), which is
# expected to recur after init unlike edits to the hook scripts themselves.
# Fails open on unknown payloads.
set -uo pipefail

. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
command -v jq >/dev/null 2>&1 || exit 0

[ "${HARNESS_ALLOW_MECHANISM_EDITS:-0}" = "1" ] && exit 0

hook_read_input
files=$(hook_affected_files)
[ -n "$files" ] || exit 0

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Optional per-repo hint appended to deny messages (e.g. "edit the template,
# not the installed copy"). Sourced from harness.conf; empty by default, so the
# generic deny contract is unchanged for repos that set nothing.
# shellcheck source=/dev/null
[ -f "$ROOT/scripts/harness.conf" ] && . "$ROOT/scripts/harness.conf" 2>/dev/null
DENY_HINT="${GUARD_DENY_HINT:-}"

# Built-in mechanism set (kit knowledge, not repo policy — repo additions
# belong in harness.conf's GUARD_PROTECTED_EXTRA, appended below).
# Repo-relative globs. Patterns without a slash also match by basename (so
# nested lint configs are covered); a LEADING SLASH anchors a pattern to the
# repo root — exact path, no basename fallback — so a same-named file nested
# elsewhere (e.g. a shipped template copy) stays editable. The harness mechanism is protected by
# default — including .github/workflows/*, because CI runs the gates and an
# agent that can edit a workflow can disarm the enforcing layer.
PROTECTED_PATHS="
scripts/hooks/*.sh
scripts/check-harness.sh
scripts/install-lib.sh
scripts/install-test-lib.sh
scripts/sync-agent-skills.sh
scripts/dev-instance.sh
scripts/dev.sh
scripts/eval*.sh
scripts/test-*.sh
scripts/.harness-manifest
scripts/kit-manifest
.claude/settings.json
.cursor/hooks.json
.cursor/sandbox.json
.codex/hooks.json
.opencode/plugins/*
/opencode.json
.devcontainer/*
.github/workflows/*
"
# 2026-07-12 probe found these five writable live, each a cheap way to
# disarm another layer before the CI manifest check catches it:
# - scripts/harness.conf: guard-secrets.sh's single pattern source;
#   post-init tailoring rides the HARNESS_ALLOW_MECHANISM_EDITS=1 escape
#   hatch above, same ceremony as any other entry in this list.
# - .claude/settings.local.json: can carry "disableAllHooks": true; absent
#   from the manifest and gitignored globally in the standard Claude Code
#   setup, so no other layer catches a bad write.
# - .mcp.json, .cursor/mcp.json, .codex/config.toml: feed
#   check-harness.sh's MCP inventory audit (#8c); opencode.json is already
#   covered above.
PROTECTED_PATHS="$PROTECTED_PATHS
scripts/harness.conf
.claude/settings.local.json
.mcp.json
.cursor/mcp.json
.codex/config.toml
"
# Repo-owned additions (lint/formatter configs and other disarmable files)
# come from harness.conf — data, not a fork of this mechanism file.
PROTECTED_PATHS="$PROTECTED_PATHS ${GUARD_PROTECTED_EXTRA:-}"

# Globs must reach `case` verbatim; without noglob the unquoted expansion of
# PROTECTED_PATHS would glob against the CWD.
set -f

# Collapse redundant `.`/`..`/`//` path segments so a crafted path like
# `scripts/./harness.conf` or `scripts/../scripts/harness.conf` can't slip past
# a literal protected-path glob that only matches the canonical form. Purely
# lexical and platform-independent — a `.` segment is always redundant and a
# `..` always cancels the preceding one. Deliberately NOT case normalization:
# on a case-insensitive filesystem `SCRIPTS/harness.conf` resolves to the
# protected file, but case-folding here would wrongly deny a genuinely-distinct
# file on a case-sensitive filesystem, so that determined variant stays covered
# by check-harness.sh's manifest verification in CI (the enforcing layer — this
# hook is a guardrail; see the header).
normalize_rel() {
    printf '%s' "$1" | awk -F/ '{
        n = 0
        for (i = 1; i <= NF; i++) {
            seg = $i
            if (seg == "" || seg == ".") continue
            if (seg == "..") { if (n > 0 && stack[n] != "..") { n--; continue } }
            stack[++n] = seg
        }
        out = ""
        for (i = 1; i <= n; i++) out = out (i > 1 ? "/" : "") stack[i]
        print out
    }'
}

# $pat is deliberately unquoted in the case patterns below: the protected
# list is globs, and case-glob matching is the point. Apply_patch paths are
# repo-relative already; absolute paths get the ROOT prefix stripped, and a
# leading ./ is stripped too (the envelope text is model-written, so
# `./scripts/…` occurs) — all three forms match the same globs.
check_file() {
    local file="$1" rel norm base pat hit
    rel="${file#"$ROOT"/}"
    rel="${rel#./}"
    # Canonicalize dot segments; keep the original if awk is somehow missing
    # (fail toward the existing literal match, never toward disabling the guard).
    norm=$(normalize_rel "$rel")
    [ -n "$norm" ] && rel="$norm"
    base=$(basename "$rel")
    for pat in $PROTECTED_PATHS; do
        hit=0
        case "$pat" in
            /*)
                # Root-anchored: matched only against the repo-relative path
                # (leading slash stripped), never by basename — a same-named
                # file nested elsewhere (e.g. the shipped template
                # opencode.json) stays editable.
                # shellcheck disable=SC2254
                case "$rel" in ${pat#/}) hit=1 ;; esac
                ;;
            *)
                # shellcheck disable=SC2254
                case "$rel" in $pat) hit=1 ;; esac
                # A slash-less pattern also matches by basename (nested configs).
                # shellcheck disable=SC2254
                case "$pat" in
                    */*) ;;
                    *) case "$base" in $pat) hit=1 ;; esac ;;
                esac
                ;;
        esac
        if [ "$hit" = "1" ]; then
            hook_deny "Blocked by scripts/hooks/guard-config.sh: '$rel' is harness mechanism or a protected config. If a check is failing, fix the code it complains about — do not edit the check. Intentional harness maintenance: re-run with HARNESS_ALLOW_MECHANISM_EDITS=1, then re-pin scripts/.harness-manifest (see check-harness.sh).${DENY_HINT:+ $DENY_HINT}"
        fi
    done
    return 0
}

# Process substitution, not a pipeline — hook_deny must exit the hook, and
# `exit 2` inside a pipeline subshell would be swallowed (see lib.sh).
while IFS= read -r f; do
    [ -n "$f" ] && check_file "$f"
done < <(printf '%s\n' "$files")

exit 0
