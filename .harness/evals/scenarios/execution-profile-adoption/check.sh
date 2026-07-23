#!/usr/bin/env bash
# Grade exact adopted tuples plus non-clobbering behavior.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fail=0

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 1; }

check() {
    if "$@"; then
        return 0
    fi
    echo "FAIL: $*"
    fail=1
}

profile_declared_once() {
    [ "$(grep -c '^EXECUTION_PROFILE_PROVIDERS=' scripts/harness/harness.conf)" -eq 1 ]
}

doc_has() {
    grep -Eiq -- "$1" docs/standards/execution-profiles.md
}

check jq -e '
    .companyPolicy == "keep-me"
    and (.permissions.deny | index("Read(**/.env)") != null)
    and .hooks.SessionStart[0].hooks[0].command == "scripts/harness/hooks/session-context.sh"
    and .sandbox.enabled == true
    and .sandbox.failIfUnavailable == true
    and .sandbox.allowUnsandboxedCommands == true
    and .sandbox.excludedCommands == []
    and .sandbox.autoAllowBashIfSandboxed == false
    and .sandbox.filesystem.allowWrite == []
    and .sandbox.filesystem.denyRead == ["~/.company"]
    and .sandbox.network.allowedDomains == []
    and (.sandbox.network.deniedDomains | index("*") != null)
    and (.sandbox.network.deniedDomains | index("blocked.company.invalid") != null)
    and .sandbox.network.allowLocalBinding == false
    and .sandbox.network.allowAllUnixSockets == false
    and any(.sandbox.credentials.files[]; .path == "~/.aws/credentials" and .mode == "deny")
    and any(.sandbox.credentials.files[]; .path == "~/.ssh" and .mode == "deny")
    and any(.sandbox.credentials.envVars[]; .name == "GITHUB_TOKEN" and .mode == "deny")
    and any(.sandbox.credentials.envVars[]; .name == "NPM_TOKEN" and .mode == "deny")
' .claude/settings.json

check python3 - .claude/settings.json .codex/config.toml <<'PY'
import json, pathlib, re, sys, tomllib

claude = json.loads(pathlib.Path(sys.argv[1]).read_text())
data = tomllib.loads(pathlib.Path(sys.argv[2]).read_text())
assert data["sandbox_mode"] == "workspace-write"
assert data["approval_policy"] == "on-request"
assert data["approvals_reviewer"] == "user"
assert data["allow_login_shell"] is False
sw = data["sandbox_workspace_write"]
assert sw == {
    "network_access": True,
    "writable_roots": [],
    "exclude_tmpdir_env_var": False,
    "exclude_slash_tmp": False,
}
proxy = data["features"]["network_proxy"]
assert proxy["enabled"] is True
assert proxy["allow_local_binding"] is True
assert proxy["domains"] == {"localhost": "allow", "127.0.0.1": "allow"}
assert proxy.get("unix_sockets", {}) == {}
assert proxy.get("dangerously_allow_non_loopback_proxy", False) is False
assert proxy.get("dangerously_allow_all_unix_sockets", False) is False
env = data["shell_environment_policy"]
assert env["inherit"] == "core"
assert env["ignore_default_excludes"] is False
assert data["company"]["keep"] is True
assert data["mcp_servers"]["localdocs"]["command"] == "local-docs"

# Provider telemetry is user/admin policy, not repo profile content. Parse the
# configs so comments and the convention's explanatory prose are irrelevant.
forbidden_keys = {
    "otel",
    "telemetry",
    "log_user_prompt",
    "log_user_prompts",
    "raw_prompt",
    "raw_prompts",
    "otel_log_user_prompts",
    "otel_log_tool_details",
    "otel_logs_exporter",
    "otel_metrics_exporter",
    "otel_traces_exporter",
    "otel_exporter_otlp_endpoint",
    "otel_exporter_otlp_headers",
    "authorization",
    "authorization_header",
    "auth_header",
}

def normalized_key(value):
    return re.sub(r"[^a-z0-9]+", "_", str(value).lower()).strip("_")

def reject_provider_telemetry(value):
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = normalized_key(key)
            assert normalized not in forbidden_keys
            assert not normalized.startswith("otel_")
            reject_provider_telemetry(child)
    elif isinstance(value, list):
        for child in value:
            reject_provider_telemetry(child)
    elif isinstance(value, str):
        assert not re.search(r"(?i)\bauthorization\s*[:=]|\bbearer\s+\S+", value)

reject_provider_telemetry(claude)
reject_provider_telemetry(data)
PY

check profile_declared_once
check grep -qx 'EXECUTION_PROFILE_PROVIDERS=".claude .codex"' scripts/harness/harness.conf
check grep -qx 'EVAL_PROFILE_HARNESS_SENTINEL="keep-existing-harness-policy"' scripts/harness/harness.conf
# The single provider declaration (v0.25.0, ADR 011) must survive the profile
# adoption untouched — the wiring facets derive from it.
check grep -q '^HARNESS_PROVIDERS=' scripts/harness/harness.conf
check grep -q '^PLANS_DIR=' scripts/harness/harness.conf
check grep -q '^SECRET_PATTERNS=' scripts/harness/harness.conf
check grep -q '^SECRET_ALLOW_PATTERNS=' scripts/harness/harness.conf
check grep -q '^MCP_ALLOWED_SERVERS=' scripts/harness/harness.conf
check test -f docs/standards/execution-profiles.md
check grep -q 'docs/standards/execution-profiles.md' AGENTS.md
check grep -q 'EVAL_PROFILE_AGENTS_SENTINEL: keep-existing-instructions' AGENTS.md
check grep -q '^## Project' AGENTS.md
check grep -q '^## Architecture' AGENTS.md
check grep -q '^## Standards & Runbooks' AGENTS.md
check grep -q '^## Quality Gates' AGENTS.md
check grep -q '^## Enforcement' AGENTS.md

# Semantic fragments keep the installed convention tailorable while proving it
# remains the self-contained provider/declaration/devcontainer/observability
# contract rather than a recognizable heading stub.
check doc_has '^## Stable repo-local floors[[:space:]]*$'
check doc_has '^### Claude Code '
check doc_has '^### Cursor '
check doc_has '^### Codex '
check doc_has '^### OpenCode '
check doc_has '^## Local-runtime network and experimental variants[[:space:]]*$'
check doc_has '^## Devcontainer authoring contract[[:space:]]*$'
check doc_has '^## Provider observability is a separate stream[[:space:]]*$'
check doc_has '^## Primary references[[:space:]]*$'
check doc_has 'EXECUTION_PROFILE_PROVIDERS'
check doc_has 'unset or empty declaration'
check doc_has 'Do not infer adoption'
check doc_has '2\.1\.187'
check doc_has 'sandbox\.json Only'
check doc_has 'administrator'
check doc_has 'OpenCode supplies permission prompts, not an OS filesystem or network sandbox'
check doc_has 'localhost'
check doc_has '127\.0\.0\.1'
check doc_has 'allow_local_binding = true'
check doc_has 'unix_sockets'
check doc_has 'dangerously_allow_non_loopback_proxy'
check doc_has 'broader local/private'
check doc_has 'Codex CLI 0\.144\.1'
check doc_has 'macOS'
check doc_has 'ownership-safe'
check doc_has 'scripts/dev\.sh down'
check doc_has 'not proof of the full runtime lifecycle'
check doc_has 'non-root'
check doc_has 'container-engine socket'
check doc_has 'postCreateCommand'
check doc_has '\.harness/var/log\.jsonl'
check doc_has 'does not join the streams automatically'
check sh -c '! grep -q "plugins/harness-kit\|skill directory" docs/standards/execution-profiles.md'
check sh -c '! grep -Eiq "OTEL_LOG_USER_PROMPTS[[:space:]]*=[[:space:]]*1|Authorization:|Bearer[[:space:]]" docs/standards/execution-profiles.md'

check cmp -s .cursor/sandbox.json "$here/fixture/cursor-sandbox.json"
check cmp -s opencode.json "$here/fixture/opencode.json"
check cmp -s .devcontainer/devcontainer.json "$here/fixture/devcontainer.json"
check cmp -s scripts/dev.sh "$here/fixture/dev.sh"

if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "pass: closed Claude + broad local/private Codex compatibility profiles adopted; weakening, teardown limit, and local state preserved"
