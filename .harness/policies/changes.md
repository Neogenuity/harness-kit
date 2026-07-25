# Risky actions: destructive git operations and irreversible deletes

The dangerous *outputs* an agent can produce in this repo — history rewrites,
tag deletion, force-pushes, and deleting recorded eval baselines or completed
plans — need a policy that says which layer stops each one, and admits honestly
which layers only warn. For hostile *inputs* (prompt injection, untrusted
fixture clones) see [untrusted-content.md](security.md).

This repo has **no production environment**: it ships templates into other
people's repos, so its own irreversible actions are all git-history and
recorded-artifact deletions.

## The three layers (label every example with one)

Each control here is exactly one class; naming it states its bypass boundary so
nobody mistakes a warning for a wall:

- **pre-action enforcement** — native permission denies, approval policies,
  sandbox / network settings. *Holds* until the user loosens the native config,
  and it is the only layer that stops a shell command **as a boundary** — but
  it is not the only one that stops one *at all*, and for reads it is often not
  the one that fires: the native deny lists are `Read(...)`-scoped and never see
  `Bash`. Cite the
  [Execution-containment row of the provider matrix](../../plugins/harness-kit/skills/harness-kit/references/provider-matrix.md).
- **in-turn advisory feedback** — the portable hooks. `guard-config.sh` denies
  mechanism / lint-config *file edits* (exit 2, mid-turn) — the protected set
  also covers `harness.conf`, the Claude Code local-settings override, and
  the per-provider MCP configs; `guard-project-policy.sh` warns once at stop
  time. `guard-secrets.sh` is **not** file-edit-scoped: it also token-scans
  shell command *text* and denies before the command runs — wired to `Bash` on
  Claude Code and to every Codex command, where reads *are* shell commands. So
  this layer, not the native one, is what actually refuses `cat <secret-file>`
  — and it is the fail-open, trivially bypassable one (indirection, globs,
  encodings). Advisory all the same: the model can reach the same effect
  another way, and every hook fails open. Never a boundary — see
  [pattern.md](../../plugins/harness-kit/skills/harness-kit/references/pattern.md).
  Expect false positives: that scan matches on **basename** and never checks
  whether the token is a path that exists, so any command whose text merely
  *names* a secret file is refused even when it reads nothing — `grep -rn .env
  docs/` and `git commit -m "clarify .env handling"` are both denied. That is
  the deliberate trade (over-denying a shell command is cheaper than missing
  `cat .env`); rephrase the command, or drop `Bash` from the matcher if this
  repo talks about secret filenames constantly. The kit wires no Cursor
  pre-edit hook (Cursor's generic `preToolUse` is pre-edit-capable but not yet
  wired — see the provider-matrix Cursor-hooks note), and OpenCode has no shell
  hooks at all, so these denials fire on Claude Code and Codex only — elsewhere
  the CI detection layer (`check-harness` manifest integrity) is the backstop,
  **for kit mechanism files only**: the manifest pins what the kit installed,
  so `GUARD_PROTECTED_EXTRA` entries have no integrity check there.
- **CI detection** — `check-harness` manifest integrity + drift checks.
  Catches an edit that slipped past the other two, *after* the fact: prevents
  merge, not the action in the turn.

## Default posture

This repo explicitly adopts all four provider profiles; the safe posture is
provider-specific and loosened only deliberately:

- **Claude Code:** writes stay inside the workspace plus declared isolated temp
  roots and sandboxed command egress is closed. A command that cannot run there
  may retry unsandboxed only through the normal user-approval flow; no command
  is pre-excluded from the sandbox. *[pre-action enforcement — OS sandbox,
  network policy, then explicit approval]*
- **Codex:** writes stay inside the workspace plus declared isolated temp roots
  and command egress is closed; `approval_policy = "on-request"` retains
  explicit escalation for a command that needs broader execution. *[pre-action
  enforcement — OS sandbox, network policy, then explicit approval]*
- **Cursor:** the committed file declares workspace-plus-temp writes and closed
  egress; effective closed egress additionally requires **sandbox.json Only**
  UI mode or administrator policy. *[pre-action enforcement — conditional
  native sandbox / network policy]*
- **OpenCode:** external paths and web tools deny while shell commands ask. Its
  policy is not an OS/filesystem/network boundary, so an approved shell can
  still reach host paths and the network. *[pre-action policy — approvals only]*

The exact key per harness is in the
[provider matrix](../../plugins/harness-kit/skills/harness-kit/references/provider-matrix.md);
this repo's adopted tuples and provider-specific limits are in
[execution-profiles.md](../../docs/standards/execution-profiles.md). **Loosening** is per-need and
reversible: allow one host for one task, then restore. Widen the narrowest
thing.

## Destructive git operations

Force-pushes (`git push --force`), tag deletion (`git tag -d`, `git push
--delete`), and history rewrites (`git rebase`, `git filter-branch`) are
one-way on a shared branch:

- Gate them at the native permission / approval layer so they prompt before
  running — an ask-rule on `Bash(git push --force*)`, or Codex
  `approval_policy = "on-request"`. *[pre-action enforcement]*
- **Hooks do not stop these.** `guard-config.sh` denies *file edits* to harness
  mechanism and lint configs; it does **not** scan shell commands, by design, so
  it cannot block a force-push or a `git tag -d`. *[in-turn advisory feedback —
  file edits only]*
- Do **not** claim `PROTECTED_PATHS` (or any hook) protects against destructive
  shell commands: it is a file-edit deny list, not a command filter.

## Deleting recorded artifacts

Recorded eval baselines (`.harness/evals/baselines.json`) and completed plans
(`docs/plans/completed/`) are the repo's memory of what shipped and how the
harness measured. Deleting one is silent data loss:

- No hook guards these paths against a shell `rm` — only the native approval
  layer prompts *[pre-action enforcement]*, and review + git history are the
  backstop *[CI detection / review]*.
- Move plans between lifecycle states with `git mv`, never delete; re-record a
  baseline via `eval-harness.sh`, never hand-delete it.
