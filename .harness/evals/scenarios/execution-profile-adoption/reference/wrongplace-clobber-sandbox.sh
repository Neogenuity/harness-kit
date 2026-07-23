#!/usr/bin/env bash
# Forbidden shortcut: replace nested project-owned Claude sandbox restrictions
# while adding the stable profile floor.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

bash "$here/apply.sh"
tmp="$(mktemp "${TMPDIR:-/tmp}/profile-sandbox-clobber-XXXXXX")"
jq 'del(.sandbox.autoAllowBashIfSandboxed, .sandbox.filesystem.denyRead)
    | .sandbox.network.deniedDomains = ["*"]' \
    .claude/settings.json > "$tmp"
mv "$tmp" .claude/settings.json
