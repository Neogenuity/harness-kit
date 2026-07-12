# Risky actions: destructive git operations and irreversible deletes

The dangerous *outputs* an agent can produce in this repo — history rewrites,
tag deletion, force-pushes, and deleting recorded eval baselines or completed
plans — need a policy that says which layer stops each one, and admits honestly
which layers only warn. For hostile *inputs* (prompt injection, untrusted
fixture clones) see [untrusted-content.md](untrusted-content.md).

This repo has **no production environment**: it ships templates into other
people's repos, so its own irreversible actions are all git-history and
recorded-artifact deletions.

## The three layers (label every example with one)

Each control here is exactly one class; naming it states its bypass boundary so
nobody mistakes a warning for a wall:

- **pre-action enforcement** — native permission denies, approval policies,
  sandbox / network settings. *Holds* until the user loosens the native config,
  and it is the only layer that stops a shell command before it runs. Cite the
  [Execution-containment row of the provider matrix](../../plugins/harness-kit/skills/harness-kit/references/provider-matrix.md).
- **in-turn advisory feedback** — the portable hooks. `guard-config.sh` denies
  mechanism / lint-config *file edits* (exit 2, mid-turn) — the protected set
  also covers `harness.conf`, the Claude Code local-settings override, and
  the per-provider MCP configs; `guard-project-policy.sh` warns once at stop
  time. Advisory: file-edit scope only, the model can reach the same effect
  another way, and every hook fails open. Never a boundary — see
  [pattern.md](../../plugins/harness-kit/skills/harness-kit/references/pattern.md).
  The kit wires no Cursor pre-edit hook (Cursor's generic `preToolUse` is
  pre-edit-capable but not yet wired — see the provider-matrix Cursor-hooks
  note), so these denials fire on Claude Code and Codex only — the CI
  detection layer (`check-harness.sh` manifest integrity) is the backstop
  there.
- **CI detection** — `check-harness.sh` manifest integrity + drift checks.
  Catches an edit that slipped past the other two, *after* the fact: prevents
  merge, not the action in the turn.

## Default posture

The safe default this repo aims for, loosened only deliberately:

- **Workspace-only writes.** Writes stay inside the working tree. *[pre-action
  enforcement — sandbox]*
- **Network only for provider-doc verification and `gh`.** The sole legitimate
  egress is re-verifying the provider matrix against live docs and GitHub
  operations via `gh`; everything else is default-deny. *[pre-action
  enforcement — sandbox / network policy]*
- **Approvals on for destructive git operations.** Force-push, tag deletion,
  history rewrite, and deletes under `docs/evals/` or `docs/plans/completed/`
  prompt. *[pre-action enforcement — approvals]*

The exact key per harness is in the
[provider matrix](../../plugins/harness-kit/skills/harness-kit/references/provider-matrix.md);
per-provider sandbox/network **templates** are the queued
[execution-sandbox-profiles.md](../plans/execution-sandbox-profiles.md) plan's
job, not this doc's. **Loosening** is per-need and reversible: allow one host
for one task, then restore. Widen the narrowest thing.

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

Recorded eval baselines (`docs/evals/baselines.json`) and completed plans
(`docs/plans/completed/`) are the repo's memory of what shipped and how the
harness measured. Deleting one is silent data loss:

- No hook guards these paths against a shell `rm` — only the native approval
  layer prompts *[pre-action enforcement]*, and review + git history are the
  backstop *[CI detection / review]*.
- Move plans between lifecycle states with `git mv`, never delete; re-record a
  baseline via `eval-harness.sh`, never hand-delete it.
