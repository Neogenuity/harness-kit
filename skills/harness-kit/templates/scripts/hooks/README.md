# Agent Hooks

Provider-agnostic hook scripts for AI coding agents. All behavior lives here
as plain executables that read the hook event JSON on stdin; each agent
harness wires them with a thin config shim. The scripts accept both the
Cursor (`file_path`) and Claude Code (`tool_input.file_path`) stdin layouts,
so one script serves every harness.

| Script | Event | Behavior |
| --- | --- | --- |
| `format.sh` | after a file edit | Runs the project formatter on the edited file (see the TAILOR block for the extension → formatter map). Fails open — never blocks an edit. |
| `guard-secrets.sh` | before a file read | Denies reads of secret-bearing files (exit code 2). Matching is **case-insensitive** (`.ENV` reads the same bytes as `.env` on macOS/Windows) and **follows symlinks** (the target is authoritative, so a link named `notes.md` → `.env` is blocked and `.env.example` → `.env` does not launder the secret). Shell commands (`cat .env` via Bash) and directory-wide searches are **not** intercepted — defense-in-depth, not a boundary; pair with the harness's native permission deny list. Regression-tested by `test-guard-secrets.sh` (CI-gated). |
| `guard-project-policy.sh` | on agent stop | Advisory: warns when newly added files (including in brand-new untracked directories) break a project invariant declared in its TAILOR block. Surfaces warnings to the agent **once** via `hook_advise_once`, then lets the run finish — never a hard block. The enforcing gate belongs in tests/CI. |
| `session-context.sh` | on session start | Prints a short orientation banner — current branch, working-tree state, active plans — so a fresh session (including subagents/worktrees) starts oriented. Plain stdout, no stdin dependency; fails open. |
| `lib.sh` | (library) | Shared helpers: stdin parsing across harness layouts, `hook_deny`, `hook_new_files`, and the `hook_advise_once` dual-harness stop protocol. Protocol pinned by `test-advise-once.sh` (CI-gated). |

## Wiring per harness

- **Claude Code** — `.claude/settings.json` (`SessionStart`, `PostToolUse` on
  `Edit|Write`, `PreToolUse` on `Read|Grep`, `Stop`). The same file also
  carries the shared permission policy: quality gates and harness scripts
  allow-listed, secret files natively denied for `Read` as a second layer
  alongside `guard-secrets.sh`.
- **Cursor** — `.cursor/hooks.json` (`afterFileEdit`, `beforeReadFile`,
  `stop`; no session-start event yet, so `session-context.sh` is Claude
  Code-only for now).
- **Other harnesses** — point the equivalent lifecycle event at the same
  script; exit code 2 means "deny", exit 0 with no output means
  "allow/continue".

## Conventions

- Scripts must be executable, depend only on `bash`, `jq`, and `git`, and
  fail open (exit 0) when a dependency or input is missing.
- Deny decisions use exit code 2 with a human-readable reason on stderr —
  both Cursor and Claude Code interpret this as a block.
- Keep policy in the scripts, not in the per-provider configs, so every
  harness enforces identical behavior.
- Every guard that denies or advises gets a `test-*.sh` regression script
  here, wired into `scripts/check-harness.sh` (CI-gated).
