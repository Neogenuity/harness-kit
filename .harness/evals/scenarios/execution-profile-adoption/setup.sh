#!/usr/bin/env bash
# Seed mixed provider state. Claude and Codex are in scope for an additive
# profile merge; Cursor, OpenCode, and the devcontainer are explicit no-touch
# controls that prove adoption is never inferred from config presence.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

mkdir -p .claude .codex .cursor .devcontainer docs/standards
cp "$here/fixture/claude-settings.json" .claude/settings.json
cp "$here/fixture/codex-config.toml" .codex/config.toml
cp "$here/fixture/cursor-sandbox.json" .cursor/sandbox.json
cp "$here/fixture/opencode.json" opencode.json
cp "$here/fixture/devcontainer.json" .devcontainer/devcontainer.json
cp "$here/fixture/dev.sh" scripts/dev.sh
chmod +x scripts/dev.sh

rm -f docs/standards/execution-profiles.md

tmp="$(mktemp "${TMPDIR:-/tmp}/profile-conf-XXXXXX")"
grep -v '^EXECUTION_PROFILE_PROVIDERS=' scripts/harness/harness.conf > "$tmp" || true
printf '%s\n' 'EVAL_PROFILE_HARNESS_SENTINEL="keep-existing-harness-policy"' >> "$tmp"
mv "$tmp" scripts/harness/harness.conf

tmp="$(mktemp "${TMPDIR:-/tmp}/profile-agents-XXXXXX")"
grep -v 'docs/standards/execution-profiles.md' AGENTS.md > "$tmp" || true
printf '%s\n' '<!-- EVAL_PROFILE_AGENTS_SENTINEL: keep-existing-instructions -->' >> "$tmp"
mv "$tmp" AGENTS.md
