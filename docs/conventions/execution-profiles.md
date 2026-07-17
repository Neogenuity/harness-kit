# Execution Profiles

Execution profiles are an explicit, provider-by-provider adoption. They set the
strongest useful repo-local floor each provider can represent without claiming
that four different products enforce the same boundary.

Declare only adopted providers in `scripts/harness.conf`:

```bash
EXECUTION_PROFILE_PROVIDERS=".claude .cursor .codex .opencode"
```

An unset or empty declaration means profiles are not adopted. A declared
provider must keep its accepted profile: every fixed stable tuple below, except
that Codex's network tuple may take the accepted experimental broad
local/private-network compatibility disjunction. Do not infer adoption from
config files that happen to exist, and never replace an existing config to
adopt a profile: merge the proposed fields, preserve hooks, MCP servers,
permissions, and local keys, then get explicit approval for the diff.

The fixed tuples are an operability contract as well as a safety floor. A
changed fixed value is drift even when it appears stricter. Only provably
additive deny hardening is accepted without defining a new profile: extra
Claude credential/domain denies and extra Cursor `networkPolicy.deny` entries
are examples. Empty extra-path and network-allow arrays must remain empty.

## Stable repo-local floors

### Claude Code (`.claude/settings.json`)

This profile requires Claude Code 2.1.187 or later because that is the minimum
version for `sandbox.credentials`. Stop and report the prerequisite on older
clients; do not substitute undocumented environment scrubbing.

Required tuples:

- `sandbox.enabled` is `true`.
- `sandbox.failIfUnavailable` is `true`.
- `sandbox.allowUnsandboxedCommands` is `true`, retaining Claude Code's normal
  permission-gated escape for commands that cannot operate inside the sandbox.
- `sandbox.excludedCommands` is absent or an empty array; listed commands always
  bypass the sandbox, even when the general unsandboxed escape hatch is off.
- `sandbox.filesystem.allowWrite` is an empty array.
- `sandbox.network.allowedDomains` is an empty array.
- `sandbox.network.deniedDomains` contains `"*"`.
- `sandbox.network.allowLocalBinding` and `allowAllUnixSockets` are `false`.
- `sandbox.network.allowUnixSockets` and `allowMachLookup` are absent or empty
  arrays.
- `sandbox.enableWeakerNetworkIsolation` and `enableWeakerNestedSandbox` are
  absent or `false`.
- `sandbox.credentials.files` denies `~/.aws/credentials` and `~/.ssh`.
- `sandbox.credentials.envVars` denies `GITHUB_TOKEN` and `NPM_TOKEN`.

This makes sandbox unavailability a hard failure, adds no writable roots,
closes sandboxed network egress, and removes named credentials from sandboxed
commands. A command that genuinely needs network or host integration — for
example `git push`, a provider CLI, or an eval runner that launches one — may
retry outside the sandbox only through Claude Code's normal permission flow and
an explicit user approval. Keep `excludedCommands` empty: predeclared bypasses
run unsandboxed automatically and skip that per-command decision. Claude
otherwise reads broadly by default, so keep the native `permissions.deny`
mirror of `SECRET_PATTERNS`; add repo-specific credentials to both controls
when recon finds them.

The official Claude settings and sandboxing references, re-verified 2026-07-17,
make these exclusions security-significant. Unix-socket exceptions can expose
powerful host services and even create sandbox-bypass paths; Mach lookup entries
grant additional macOS XPC/Mach service access. The weaker network-isolation
mode opens the system TLS trust service and a potential exfiltration path, while
the weaker nested-sandbox mode exposes process information and assumes an outer
container already supplies the missing isolation. Those compatibility
exceptions are outside the stable floor; adopt them only as a separately named
weakening with an independently reviewed boundary.

Repo settings are not an administrator lock. Settings at other scopes can add
some array-valued exceptions, including excluded commands. Organizations that
need centrally enforced read and network allowlists use managed
`allowManagedReadPathsOnly` and `allowManagedDomainsOnly`. Claude's sandbox is
supported on macOS, Linux, and WSL2, not native Windows.

### Cursor (`.cursor/sandbox.json`)

Required tuples:

- `type` is `"workspace_readwrite"`.
- `additionalReadwritePaths` and `additionalReadonlyPaths` are empty arrays.
- `disableTmpWrite` is `false`; `/tmp` and the system temp locations are the
  declared write roots outside the workspace.
- `enableSharedBuildCache` is `false`.
- `networkPolicy.default` is `"deny"`, `allow` is an empty array, and `deny` is
  an array. The template starts `deny` empty; additive deny entries are allowed.

This file describes the committed floor, not the complete effective policy.
Cursor's default UI mode is **sandbox.json + Defaults**, which adds a built-in
domain allowlist, and the UI also offers **Allow All**. Closed egress therefore
requires the user to select **sandbox.json Only** or an administrator to lock
the policy. Team-admin and hardcoded policies layer above repo configuration;
path lists from lower scopes union rather than replacing one another.

Cursor uses Seatbelt on macOS and Landlock/seccomp with a Bubblewrap fallback
on Linux. If the Linux requirements are unavailable, commands fall back to the
approval path rather than gaining a silently equivalent OS boundary. Its
hardcoded policy blocks loopback/private destinations, so the kit does not
claim a narrow repo-local app profile for Cursor.

### Codex (`.codex/config.toml`)

Declared Codex profile validation requires Python 3.11 or later with the
standard-library `tomllib` parser. Without it, the complete TOML file cannot be
validated and the profile is reported as unverifiable rather than being
approved by a partial parser.

Required tuples:

- `sandbox_mode = "workspace-write"`.
- `approval_policy = "on-request"` and `approvals_reviewer = "user"`.
- `allow_login_shell = false`.
- `sandbox_workspace_write.network_access = false`.
- `sandbox_workspace_write.writable_roots = []`.
- `sandbox_workspace_write.exclude_tmpdir_env_var = false` and
  `exclude_slash_tmp = false`; `$TMPDIR` and `/tmp` are the declared temp roots.
- `shell_environment_policy.inherit = "core"` and
  `ignore_default_excludes = false`, retaining Codex's default filtering of
  environment names containing `KEY`, `SECRET`, or `TOKEN`.

On native Windows, `[windows] sandbox = "elevated"` is the recommended mode.
`"unelevated"` is an explicit reduced-assurance fallback when administrator
setup is unavailable. The repo-local profile does not configure provider
telemetry: project `.codex/config.toml` ignores `otel` settings.

### OpenCode (`opencode.json`)

Required tuples:

- `permission.external_directory` is `"deny"`.
- `permission.bash` is `"ask"`.
- `permission.webfetch` and `permission.websearch` are `"deny"`.
- `permission.read` keeps the full native mirror of `SECRET_PATTERNS`.

OpenCode supplies permission prompts, not an OS filesystem or network sandbox.
A shell approved once, approved for the session, or auto-approved with
`opencode --auto` can still access host paths and network destinations. These
tuples prove only the native permission posture; they do not make an OpenCode
session equivalent to the Claude, Cursor, or Codex sandbox. Use a separately
reviewed container or VM when that boundary is required.

## Local-runtime network and experimental variants

The stable profile deliberately closes command network access. Do not broaden
it merely because a runnable app exists. Adopt a variant only after the user
confirms the app's local-runtime need.

Codex is the only provider in this set with an opt-in local-runtime network
variant the kit accepts. It is experimental and explicitly broader than
localhost-only access:

```toml
[sandbox_workspace_write]
network_access = true
writable_roots = []
exclude_tmpdir_env_var = false
exclude_slash_tmp = false

[features.network_proxy]
enabled = true
allow_local_binding = true
domains = { "localhost" = "allow", "127.0.0.1" = "allow" }
```

Keep every other stable Codex tuple. No public domain or wildcard is allowed in
the domain map, so public destinations remain outside the allowlist. However,
`allow_local_binding = true` also permits broader local/private-network reach,
including loopback, link-local, and private destinations; the exact
`localhost` and `127.0.0.1` entries do not make this a localhost-only boundary.
Leave `unix_sockets` unset, and leave
`dangerously_allow_non_loopback_proxy` and
`dangerously_allow_all_unix_sockets` absent or `false`. Those socket/proxy
bypasses are not part of this compatibility profile.

Live verification on 2026-07-14 with Codex CLI 0.144.1 on macOS found that
`allow_local_binding = false` blocked concurrent worktree runtime startup.
Setting it to `true` permitted concurrent `up`, `health`, `seed`, and local HTTP
access, while an `https://example.com/` probe remained proxy-blocked. The same
sandbox denied the `ps` inspection used by ownership-safe `scripts/dev.sh down`,
so this is network compatibility, not proof of the full runtime lifecycle. Do
not present a direct process kill as equivalent to ownership-safe teardown.
`network_proxy` is experimental; re-verify both the public probe and runtime
behavior on the installed Codex version.

Claude can express strict localhost-only access only with a managed domain
allowlist locked by `allowManagedDomainsOnly`; removing the repo's `"*"` deny
leaves new public hosts approval-gated rather than closed. Cursor hard-blocks
private and loopback targets in its higher-priority policy. OpenCode has no
enforceable network split. Report those variants as unavailable instead of
silently switching to broad network access or unsandboxed execution.

## Devcontainer authoring contract

A devcontainer is an optional second boundary, not a generic template. Init or
update may author `.devcontainer/devcontainer.json` only when all of the
following are true:

1. Recon finds and the user confirms a real image, Dockerfile, or Compose
   service to build from.
2. The user explicitly opts in after seeing the proposed image/build source,
   non-root user, mounts, forwarded ports, and lifecycle commands.
3. No existing `.devcontainer/` file is overwritten; existing files receive a
   proposed diff only.
4. The container runs as a non-root user and mounts neither host credentials
   nor a container-engine socket. Do not forward SSH/GPG agents or copy auth
   files by default.
5. Repo code does not run automatically from `postCreateCommand` or
   `postStartCommand`. Build the container first, then explicitly run the
   repo's documented gates inside it.

For an application repo, use its already-authored `scripts/dev.sh` lifecycle
inside the built container; do not guess framework commands or add a second
launcher. Reuse the instance when `health` already reports ready; otherwise run
`up`, wait for readiness with `health`, then exercise `seed` and ownership-safe
`down` under the same ownership and cleanup rules as the dev-runtime
convention. If no concrete
image/build source or non-root runtime can be confirmed, defer the devcontainer
instead of emitting placeholders.

## Provider observability is a separate stream

`.harness/log.jsonl` records this repo's guard denials, advice, and lint
feedback. Provider telemetry has different schemas, retention, scope, and
privacy controls; the kit does not join the streams automatically.

| Provider | Available signal | Configuration/export scope | Privacy floor |
| --- | --- | --- | --- |
| Claude Code | OpenTelemetry metrics and log/events; traces are beta | User, environment, or managed configuration; no exporter endpoint or header belongs in the repo template | Prompt content is redacted by default; do not enable raw prompt or tool-content logging from repo config |
| Cursor | Project hooks can write purpose-built local audit events; team and enterprise hook distribution is admin-scoped | Hook output is custom repo/admin policy, not a portable provider telemetry exporter | Hook payloads may contain prompts, commands, paths, and tool output; select fields rather than recording raw payloads |
| Codex | OpenTelemetry logs, metrics, and traces | User-level config only; project `.codex/config.toml` ignores `otel` | Raw user prompts are off by default; keep them off and store no collector credentials in the repo |
| OpenCode | `opencode stats`, JSON session export, and local diagnostic logs | Local CLI/session operations; `opencode export --sanitize` is the safer manual export | Session exports can contain transcript/file data; use `--sanitize` and do not auto-share |

Do not ship collectors, endpoints, authorization headers, real hostnames,
credentials, or raw-prompt opt-ins. A future correlation schema may join
provider sessions to `.harness/log.jsonl`; until then, report them separately.

## Review checklist

- [ ] Only explicitly adopted providers are declared.
- [ ] Existing provider keys, hooks, permissions, MCP servers, and secret-deny
      mirrors survived the merge.
- [ ] `bash scripts/check-harness.sh` validates every declared tuple.
- [ ] Any temp root, network exception, external path, excluded command, or
      Windows fallback is named as a weakening.
- [ ] Provider telemetry remains separate and does not capture raw prompts.
- [ ] A devcontainer, if adopted, was authored from confirmed repo evidence,
      built, exercised, and never mounted host credentials or a host socket.

## Primary references

Provider facts were re-verified 2026-07-14 against:

- Claude Code sandboxing, settings, and monitoring:
  <https://code.claude.com/docs/en/sandboxing>,
  <https://code.claude.com/docs/en/settings>, and
  <https://code.claude.com/docs/en/monitoring-usage>
- Cursor sandbox and run modes:
  <https://cursor.com/docs/reference/sandbox> and
  <https://cursor.com/docs/agent/security/run-modes>; Cursor hooks and managed
  hook distribution: <https://cursor.com/docs/hooks>
- Codex sandbox/configuration and Windows sandbox:
  <https://learn.chatgpt.com/docs/agent-approvals-security>,
  <https://learn.chatgpt.com/docs/config-file/config-reference>, and
  <https://learn.chatgpt.com/docs/windows/windows-sandbox>
- OpenCode permissions and CLI:
  <https://opencode.ai/docs/permissions/> and
  <https://opencode.ai/docs/cli/>
