# Agent Hooks

Provider-agnostic hook scripts for AI coding agents. All behavior lives here
as plain executables that read the hook event JSON on stdin; each agent
harness wires them with a thin config shim. The scripts accept three stdin
layouts — Cursor (top-level `file_path`), Claude Code (nested
`tool_input.file_path`), and Codex (no file path; apply_patch envelopes and
shell commands inside `tool_input.command`) — via `lib.sh:
hook_affected_files`, so one script serves every harness.

| Script | Event | Behavior |
| --- | --- | --- |
| `format.sh` | after a file edit | Runs the project formatter on the edited file, then the fast linter for that file type, feeding findings back to the agent via `hook_feedback` so it self-corrects within the turn (see the two TAILOR maps). Fails open — never blocks an edit; findings are feedback (stderr + exit 2 on Claude Code/Codex, stdout on Cursor), not a block. Protocol pinned by `test-format-feedback.sh` (CI-gated). |
| `guard-secrets.sh` | before a file read | Denies reads of secret-bearing files (exit code 2). Patterns come from `scripts/harness.conf` (`SECRET_PATTERNS` / `SECRET_ALLOW_PATTERNS`) — the single source that `check-harness.sh` also verifies the native deny lists against. Matching is **case-insensitive** (`.ENV` reads the same bytes as `.env` on macOS/Windows) and **follows symlinks** (the target is authoritative, so a link named `notes.md` → `.env` is blocked and `.env.example` → `.env` does not launder the secret). Also denies apply_patch **writes** to secret files and token-scans shell command strings — the only live secret layer on Codex, where reads are shell commands — best-effort and bypassable (indirection, globs, encodings); directory-wide searches are **not** intercepted. Defense-in-depth, not a boundary; pair with the harness's native permission deny list. Regression-tested by `test-guard-secrets.sh` (CI-gated). |
| `guard-config.sh` | before a file edit/write | Denies agent edits to the harness mechanism (hook scripts, sync/check/verify machinery, the manifest, hook wiring, CI gate) plus TAILOR-listed linter/formatter configs — an agent that can edit the guard can silence it. Escape hatch for intentional maintenance: run with `HARNESS_ALLOW_MECHANISM_EDITS=1`, then re-pin `scripts/.harness-manifest`. Codex apply_patch edits (including multi-file patches) are parsed and denied; shell edits (`sed` via Bash) are **not** intercepted — read vs write is indistinguishable from command text — so the manifest verification in `check-harness.sh` is the enforcing CI layer. Regression-tested by `test-guard-config.sh` (CI-gated). |
| `guard-project-policy.sh` | on agent stop | Advisory: warns when newly added files (including in brand-new untracked directories) break a project invariant declared in its TAILOR block. Surfaces warnings to the agent **once** via `hook_advise_once`, then lets the run finish — never a hard block. The enforcing gate belongs in tests/CI. |
| `session-context.sh` | on session start | Prints a short orientation banner — current branch, working-tree state, active plans — so a fresh session (including subagents/worktrees) starts oriented. Plain stdout, no stdin dependency; fails open. |
| `lib.sh` | (library) | Shared helpers: stdin parsing across harness layouts (`hook_affected_files` — direct file-path fields plus Codex apply_patch envelopes, pinned by `test-affected-files.sh`), `hook_command_string`, `hook_deny`, `hook_new_files`, and the `hook_advise_once` stop protocol (pinned by `test-advise-once.sh`). Both CI-gated. |

## Wiring per harness

- **Claude Code** — `.claude/settings.json` (`SessionStart`, `PostToolUse` on
  `Edit|Write`, `PreToolUse` on `Read|Grep` → guard-secrets and on
  `Edit|Write` → guard-config, `Stop`). The same file also carries the shared
  permission policy: quality gates and harness scripts allow-listed, secret
  files natively denied for `Read` as a second layer alongside
  `guard-secrets.sh`.
- **Cursor** — `.cursor/hooks.json` (`sessionStart`, `afterFileEdit`,
  `beforeReadFile`, `stop`). Cursor has no pre-edit event (2026-07), so
  `guard-config.sh` cannot fire there — the manifest verification in
  `check-harness.sh` is the backstop.
- **Codex** — `.codex/hooks.json` (`SessionStart`, `PreToolUse`,
  `PostToolUse`, `Stop`); hooks are GA/default-on, but project-local
  configs load only when the project is trusted. Codex payloads carry no
  file path: the guards and `format.sh` parse apply_patch envelopes out of
  `tool_input.command` (`lib.sh:hook_affected_files`), and
  `guard-secrets.sh` adds a best-effort token scan of shell commands (Codex
  reads files via shell). Keep the native permission/trust layer as a
  second guard. Stop hooks must emit JSON when exiting 0 —
  `hook_advise_once` handles that contract.
- **OpenCode** — no shell hooks. A small TS plugin in `.opencode/plugins/`
  hooking `tool.execute.before`/`after`, shelling out to these scripts and
  throwing on exit 2 (OpenCode's block mechanism), is the documented wiring
  path — but the kit ships no such shim template yet (descoped 2026-07-13),
  so OpenCode is not hook-wired. Its native `opencode.json` `permission.read`
  denies and the `check-harness.sh` manifest verification are the backstop.
- **Other harnesses** — point the equivalent lifecycle event at the same
  script; exit code 2 means "deny", exit 0 with no output means
  "allow/continue".

## Conventions

- Scripts must be executable, depend only on `bash`, `jq`, and `git`, and
  fail open (exit 0) when a dependency or input is missing.
- Deny decisions use exit code 2 with a human-readable reason on stderr —
  Claude Code, Cursor, and Codex all interpret this as a block.
- Keep policy in the scripts, not in the per-provider configs, so every
  harness enforces identical behavior.
- Every guard that denies or advises gets a `test-*.sh` regression script
  here, wired into `scripts/check-harness.sh` (CI-gated).
- Every deny / advisory / lint-findings event is appended as one JSON line to
  `.harness/log.jsonl` (git-ignored) via `hook_log` — toggle with
  `HARNESS_LOG` in `harness.conf` (env overrides win). The audit workflow
  summarizes the log; repeated entries mark the next mistake to engineer
  away.
