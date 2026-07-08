# Agent Hooks

Provider-agnostic hook scripts for AI coding agents. All behavior lives here
as plain executables that read the hook event JSON on stdin; each agent
harness wires them with a thin config shim. The scripts accept both the
Cursor (`file_path`) and Claude Code/Codex (`tool_input.file_path`) stdin
layouts, so one script serves every harness.

| Script | Event | Behavior |
| --- | --- | --- |
| `format.sh` | after a file edit | Runs the project formatter on the edited file, then the fast linter for that file type, feeding findings back to the agent via `hook_feedback` so it self-corrects within the turn (see the two TAILOR maps). Fails open — never blocks an edit; findings are feedback (stderr + exit 2 on Claude Code/Codex, stdout on Cursor), not a block. Protocol pinned by `test-format-feedback.sh` (CI-gated). |
| `guard-secrets.sh` | before a file read | Denies reads of secret-bearing files (exit code 2). Patterns come from `scripts/harness.conf` (`SECRET_PATTERNS` / `SECRET_ALLOW_PATTERNS`) — the single source that `check-harness.sh` also verifies the native deny lists against. Matching is **case-insensitive** (`.ENV` reads the same bytes as `.env` on macOS/Windows) and **follows symlinks** (the target is authoritative, so a link named `notes.md` → `.env` is blocked and `.env.example` → `.env` does not launder the secret). Shell commands (`cat .env` via Bash) and directory-wide searches are **not** intercepted — defense-in-depth, not a boundary; pair with the harness's native permission deny list. Regression-tested by `test-guard-secrets.sh` (CI-gated). |
| `guard-project-policy.sh` | on agent stop | Advisory: warns when newly added files (including in brand-new untracked directories) break a project invariant declared in its TAILOR block. Surfaces warnings to the agent **once** via `hook_advise_once`, then lets the run finish — never a hard block. The enforcing gate belongs in tests/CI. |
| `session-context.sh` | on session start | Prints a short orientation banner — current branch, working-tree state, active plans — so a fresh session (including subagents/worktrees) starts oriented. Plain stdout, no stdin dependency; fails open. |
| `lib.sh` | (library) | Shared helpers: stdin parsing across harness layouts, `hook_deny`, `hook_new_files`, and the `hook_advise_once` dual-harness stop protocol. Protocol pinned by `test-advise-once.sh` (CI-gated). |

## Wiring per harness

- **Claude Code** — `.claude/settings.json` (`SessionStart`, `PostToolUse` on
  `Edit|Write`, `PreToolUse` on `Read|Grep`, `Stop`). The same file also
  carries the shared permission policy: quality gates and harness scripts
  allow-listed, secret files natively denied for `Read` as a second layer
  alongside `guard-secrets.sh`.
- **Cursor** — `.cursor/hooks.json` (`sessionStart`, `afterFileEdit`,
  `beforeReadFile`, `stop`).
- **Codex** — `.codex/hooks.json` (`SessionStart`, `PreToolUse`,
  `PostToolUse`, `Stop`); loads only when the project is trusted. Codex has
  no dedicated Read tool (files are read via shell), so `guard-secrets.sh`
  fails open on payloads without a file path — the native permission/trust
  layer stays the primary guard there. Verify the `PostToolUse` payload
  carries a file path for your Codex version before relying on `format.sh`.
- **OpenCode** — no shell hooks; a small TS plugin in `.opencode/plugins/`
  hooks `tool.execute.before`/`after`, shells out to these scripts, and
  throws on exit 2 (OpenCode's block mechanism).
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
