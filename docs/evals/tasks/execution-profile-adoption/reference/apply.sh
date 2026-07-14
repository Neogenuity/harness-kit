#!/usr/bin/env bash
# Reference solution: merge only the requested profile keys.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
task_dir="$(cd "$here/.." && pwd)"
source_root="$(git -C "$task_dir" rev-parse --show-toplevel)"

tmp="$(mktemp "${TMPDIR:-/tmp}/profile-claude-XXXXXX")"
jq '
  .sandbox.enabled = true
  | .sandbox.failIfUnavailable = true
  | .sandbox.allowUnsandboxedCommands = false
  | .sandbox.excludedCommands = []
  | .sandbox.filesystem.allowWrite = []
  | .sandbox.network.allowedDomains = []
  | .sandbox.network.deniedDomains = ((.sandbox.network.deniedDomains // []) + ["*"] | unique)
  | .sandbox.network.allowLocalBinding = false
  | .sandbox.network.allowAllUnixSockets = false
  | .sandbox.credentials.files = (
      (.sandbox.credentials.files // [])
      + [
          {path: "~/.aws/credentials", mode: "deny"},
          {path: "~/.ssh", mode: "deny"}
        ]
      | unique_by([.path, .mode])
    )
  | .sandbox.credentials.envVars = (
      (.sandbox.credentials.envVars // [])
      + [
          {name: "GITHUB_TOKEN", mode: "deny"},
          {name: "NPM_TOKEN", mode: "deny"}
        ]
      | unique_by([.name, .mode])
    )
' .claude/settings.json > "$tmp"
mv "$tmp" .claude/settings.json

tmp="$(mktemp "${TMPDIR:-/tmp}/profile-codex-XXXXXX")"
cat > "$tmp" <<'TOML'
sandbox_mode = "workspace-write"
approval_policy = "on-request"
approvals_reviewer = "user"
allow_login_shell = false

[sandbox_workspace_write]
network_access = true
writable_roots = []
exclude_tmpdir_env_var = false
exclude_slash_tmp = false

[shell_environment_policy]
inherit = "core"
ignore_default_excludes = false

[features.network_proxy]
enabled = true
allow_local_binding = true
domains = { "localhost" = "allow", "127.0.0.1" = "allow" }
unix_sockets = {}

TOML
cat .codex/config.toml >> "$tmp"
mv "$tmp" .codex/config.toml

tmp="$(mktemp "${TMPDIR:-/tmp}/profile-conf-XXXXXX")"
grep -v '^EXECUTION_PROFILE_PROVIDERS=' scripts/harness.conf > "$tmp" || true
printf '%s\n' 'EXECUTION_PROFILE_PROVIDERS=".claude .codex"' >> "$tmp"
mv "$tmp" scripts/harness.conf

cp "$source_root/plugins/harness-kit/skills/harness-kit/templates/docs/conventions/execution-profiles.md" \
    docs/conventions/execution-profiles.md

if ! grep -q 'docs/conventions/execution-profiles.md' AGENTS.md; then
    printf '\n- [docs/conventions/execution-profiles.md](docs/conventions/execution-profiles.md) — exact adopted provider execution floors and limits\n' >> AGENTS.md
fi

# Deliberately do not touch the task's Cursor/OpenCode/devcontainer controls.
test -f "$task_dir/fixture/cursor-sandbox.json"
