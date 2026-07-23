# Development runtime contract

Application repositories expose one repository-local interface for running and
observing the app:

```text
scripts/dev.sh up|health|seed|down
```

Agents and humans use this interface instead of guessing framework commands.
Libraries, documentation repositories, and other projects with no runnable
application do not need `scripts/dev.sh` or this convention.

<!-- TAILOR: replace the runtime map below with this application's real boot,
     readiness, deterministic-reset, port, log, and trace behavior. Keep the
     JSON schema and lifecycle semantics unchanged. `scripts/dev.sh` is an
     authored adapter for this repo, not a generic harness-kit template. -->

## Runtime map

| Concern | This application |
| --- | --- |
| Boot command | `{{BOOT_COMMAND}}` |
| Readiness check | `{{READINESS_CHECK}}` |
| Deterministic seed/reset | `{{SEED_RESET_COMMAND}}` |
| Port injection | `{{PORT_ENV_OR_FLAG}}` |
| Candidate port | base `{{PORT_BASE}}`, span `{{PORT_SPAN}}`, namespace `{{PORT_NAMESPACE_OR_NONE}}` |
| Logs | `{{REPO_RELATIVE_LOG_PATH}}` |
| Traces | `{{REPO_RELATIVE_TRACE_PATH_OR_EMPTY}}` |

## JSON v1 response

Every recognized action prints exactly one compact JSON object to stdout and
nothing else. Diagnostics belong on stderr or in the reported log. All eight
keys below are required; a failure object may add only `message` and must exit
nonzero.

| Key | v1 type and meaning |
| --- | --- |
| `schema_version` | Integer `1`. |
| `action` | String: `up`, `health`, `seed`, or `down`; it matches the requested action. |
| `status` | String: `ready`, `seeded`, `stopped`, `unhealthy`, or `error`, with the action-specific meanings below. |
| `instance` | Lowercase helper suffix matching `^h[0-9a-f]{12}$`, returned by `scripts/harness/lib/dev-instance.sh suffix`; it identifies the current physical Git worktree. |
| `url` | String for this instance; it may be empty when stopped or on error. |
| `logs` | Nonempty repo-relative path string for this instance's application log. |
| `traces` | Repo-relative path string for this instance's trace artifact, or an empty string when the app has no traces. |
| `started` | Boolean; `true` only when this invocation of `up` launched the instance. Reused `up` and every other action report `false`. |

Successful responses use these status/exit pairs:

| Action | Success status | Required behavior |
| --- | --- | --- |
| `up` | `ready`, exit 0 | Idempotently start or reuse this worktree's instance, wait for readiness, and never seed. `started` says whether this call launched it. |
| `health` | `ready`, exit 0 | Read state only. Do not start, restart, seed, repair, or remove anything. |
| `seed` | `seeded`, exit 0 | Require a healthy instance, then reset it to the same known development data on every call. |
| `down` | `stopped`, exit 0 | Idempotently stop only the instance owned by this physical worktree. An already-stopped instance is success. |

`health` exits nonzero with `stopped` when this worktree has no running
instance and with `unhealthy` when its process is running but not ready. Other
recognized-action failures use `error`, may add `message`, and exit nonzero. A
failed `up` never reports `ready`; a failed `seed` never reports `seeded`.

Example response shape (values are illustrative, not a port allocation rule):

```json
{"schema_version":1,"action":"up","status":"ready","instance":"h0123456789ab","url":"http://127.0.0.1:43123","logs":".harness/var/dev/h0123456789ab/app.log","traces":"","started":true}
```

## Worktree ownership and state

- Keep all runtime state and artifacts under `.harness/var/dev/`, which is
  git-ignored. `logs` and nonempty `traces` paths remain relative to the repo;
  never return host-absolute or plugin-cache paths.
- Derive the instance from the physical worktree root, not the branch name or
  caller's spelling of a symlinked path. Use
  `scripts/harness/lib/dev-instance.sh suffix [namespace]`; an optional namespace separates
  multiple services in the same worktree.
- Choose a candidate port with
  `scripts/harness/lib/dev-instance.sh port <base> <span> [namespace]`, unless
  `HARNESS_DEV_PORT` supplies an explicit override. The helper hashes the
  physical worktree identity into a finite span: its result is deterministic,
  not guaranteed unique.
- Before launch, check the candidate port. If another worktree or foreign
  process owns it, fail with `status: "error"`; do not reuse or kill that
  process. `down` likewise acts from recorded current-worktree ownership, never
  from "whatever is listening on the port."
- Keep enough ownership state under `.harness/var/dev/` to distinguish reuse from
  a stale PID or a foreign listener. Do not make branch renames change the
  instance identity.

## Implementation boundary

`scripts/harness/lib/dev-instance.sh` is harness mechanism and may be upgraded from the
kit. `scripts/dev.sh` is repo-specific policy: init authors it from the runtime
map above, marks it executable, and manifest-pins it as tailored. There is no
generic `dev.sh` template. Updates and audits may offer app repositories this
contract, but never add or overwrite the script, convention, or verification
skill without explicit opt-in.
