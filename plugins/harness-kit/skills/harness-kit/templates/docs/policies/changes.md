# Risky actions: destructive commands and production writes

The dangerous *outputs* an agent can produce — history rewrites, bulk deletes,
data-store drops, writes to production — need a policy that says which layer
stops each one, and admits honestly which layers only warn. For hostile
*inputs* (prompt injection, untrusted clones) see
`.harness/policies/security.md`.

<!-- TAILOR: set the "Default posture" values to your real defaults and the
     "Production environments" list to your real prod surfaces. Replace the
     destructive-command examples with the ones that actually bite in this repo.
     Keep the layer label on every example — a reviewer checks that no advisory
     layer is described as enforcement. Delete "Production environments" if this
     repo has no production surface. -->

## The three layers (label every example with one)

Each control here is exactly one class; naming it states its bypass boundary so
nobody mistakes a warning for a wall:

- **pre-action enforcement** — native permission denies, approval policies,
  sandbox / network settings. *Holds* until the user loosens the native config,
  and it is the only layer that stops a shell command before it runs. When this
  repo adopts execution profiles, cite the exact provider-specific floor in
  `docs/standards/execution-profiles.md`.
- **in-turn advisory feedback** — the portable hooks. `guard-config.sh` denies
  mechanism / lint-config *file edits* (exit 2, mid-turn) — the protected set
  also covers `harness.conf`, the Claude Code local-settings override, and
  the per-provider MCP configs; `guard-project-policy.sh` warns once at stop
  time. Advisory: file-edit scope only, the model can reach the same effect
  another way, and every hook fails open. Never a boundary. The kit wires no
  Cursor pre-edit hook (Cursor's generic `preToolUse` is pre-edit-capable but
  not yet wired — see the provider-matrix Cursor-hooks note), so these
  denials fire on Claude Code and Codex only — on Cursor, CI detection
  (`check-harness` manifest integrity) is the backstop.
- **CI detection** — `check-harness` manifest integrity + drift checks.
  Catches an edit that slipped past the other two, *after* the fact: prevents
  merge, not the action in the turn.

## Default posture

<!-- TAILOR: keep these bullets only for profiles the repo actually declares.
     Unset/empty EXECUTION_PROFILE_PROVIDERS means unadopted, not enforced. -->

When explicitly adopted, the safe profile is provider-specific and loosened
only deliberately:

- **Claude Code:** workspace plus declared isolated temp roots and closed
  sandboxed command egress. A command that cannot run there may retry
  unsandboxed only through the normal user-approval flow; no command is
  pre-excluded from the sandbox. *[pre-action enforcement — OS sandbox,
  network policy, then explicit approval]*
- **Codex:** workspace plus declared isolated temp roots and closed command
  egress; `approval_policy = "on-request"` retains explicit escalation for a
  command that needs broader execution. *[pre-action enforcement — OS sandbox,
  network policy, then explicit approval]*
- **Cursor:** the committed file declares workspace-plus-temp writes and closed
  egress, but effective closed egress also requires **sandbox.json Only** UI
  mode or administrator policy. *[pre-action enforcement — conditional native
  sandbox / network policy]*
- **OpenCode:** external paths and web tools deny; shell commands ask. This is a
  permission posture, not an OS/filesystem/network boundary. *[pre-action
  policy — approvals only]*

`EXECUTION_PROFILE_PROVIDERS` is the adoption source of truth; unset or empty
means these floors are unadopted even if provider files exist. The exact tuples,
temp roots, local/private compatibility weakenings, and administrator-only
limits are in `docs/standards/execution-profiles.md`. **Loosening** is per-need and
reversible: allow one host for one task, widen one write path, then restore.
Widen the narrowest thing.

## Destructive commands

History rewrites (`git push --force`, `git reset --hard` on shared branches),
recursive deletes (`rm -rf`), and data-store drops (`DROP TABLE`, redis
`FLUSHALL`) are one-way:

- Gate them at the native permission / approval layer so they prompt or deny
  before running — an ask-rule on `Bash(git push --force*)`, or Codex
  `approval_policy = "on-request"`. *[pre-action enforcement]*
- **Hooks do not stop these.** `guard-config.sh` denies *file edits* to harness
  mechanism and lint configs; it does **not** scan shell commands, by design, so
  it cannot block an `rm -rf` or a force-push. *[in-turn advisory feedback —
  file edits only]*
- Do **not** claim `PROTECTED_PATHS` (or any hook) protects against destructive
  shell commands: it is a file-edit deny list, not a command filter. Shell-level
  destruction is the native layer's job, with CI as the backstop.

## Production environments

Treat any prod credential, host, or data store as out of scope for an agent by
default:

- Keep prod hostnames and DSNs out of files the agent reads. The native
  secret-read deny list and sandbox credential scrubbing enforce it
  *[pre-action enforcement]*; the portable `guard-secrets.sh` hook is in-turn
  feedback on top *[in-turn advisory feedback]*.
- Destructive prod operations are human-run: document the command, don't wire an
  agent path to it. There is no hook that makes this safe — only not building
  the path does.
