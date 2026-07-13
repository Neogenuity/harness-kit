# Security Policy

harness-kit ships agent-safety machinery — guard hooks, secret-read denial,
mechanism-protection, a CI drift gate — into other people's repositories.
A flaw in that machinery is a security issue for every repo that installed
it, not just this one. This document covers how to report one privately,
what response to expect, and which versions get fixes.

## Scope

In scope: anything under `plugins/harness-kit/` (the distributed skill,
including `templates/scripts/` — the hooks and gates it installs into a
target repo) and this repo's own installed copy under `scripts/`,
`.claude/`, `.cursor/`, `.codex/`, `.opencode/`, `.agents/`. Examples: a
secret-read guard (`guard-config.sh` / the `SECRET_PATTERNS` deny list) that
can be bypassed to read a credential it claims to block; a mechanism-edit
guard that can be bypassed to silently modify protected files; a hook that
crashes in a way that blocks a legitimate agent turn instead of failing
open; a manifest/checksum check that can be spoofed to make a tampered file
look pristine.

**Before reporting, read
[docs/conventions/risky-actions.md](docs/conventions/risky-actions.md).**
It states, honestly, which layer stops what: the portable hooks are
**advisory, file-edit scope only, and fail open by design** — they do not
scan or block shell commands (no hook stops a `git push --force` or an
`rm -rf`), and a determined agent can often reach the same effect another
way. That is documented behavior, not a vulnerability. A report is most
useful when it identifies a gap between what the kit *claims* (in
`risky-actions.md`, `pattern.md`, or a hook's own deny message) and what it
*actually* does — not a gap between advisory feedback and a hard boundary
the kit never claimed to provide.

Out of scope: vulnerabilities in a target repo's own tailored policy (a
`TAILOR` block or `harness.conf` value a user filled in), or in a third-party
provider's agent runtime (Claude Code, Cursor, Codex, OpenCode) itself —
report those upstream.

## Reporting privately

Do not open a public GitHub issue for a suspected vulnerability. Use one of:

1. **GitHub Security Advisories** (preferred once the repo's Security tab is
   available to you): open a private advisory via the repo's Security tab →
   "Report a vulnerability". This keeps the report and any discussion
   private until a fix ships.
2. **Email**: [chase@neogenuity.com](mailto:chase@neogenuity.com) if the
   Security tab isn't available to you (e.g. the repo is still private, or
   you don't have GitHub access). Include repro steps, the affected
   file(s)/version, and the impact you're claiming.

Please include: the affected version (`plugins/harness-kit/VERSION` or the
tag), which guard/gate is involved, a minimal repro, and what you'd expect
the guard to do instead.

## Response window

This is a small, solo-maintained project pre-1.0 — response times are
best-effort, not contractual:

- **Acknowledgment**: target within 5 business days.
- **Triage** (confirmed vs. not, scope, severity): target within 10 business
  days of acknowledgment.
- **Fix or documented mitigation**: best-effort, prioritized by severity —
  a confirmed bypass of a secret-read or mechanism-protection guard is
  treated as high priority; a hook that fails open when it should have
  denied is treated as medium (fail-open is the designed default — see
  [ADR 001](docs/architecture/decisions/001-advisory-stop-hooks.md) — so the
  question is whether the *specific* guard's own contract was violated).

## Supported versions

Pre-1.0 (all `0.x` releases): **only the latest tagged release** receives
fixes. There is no maintained branch for older `0.x` versions — the project
moves fast enough pre-1.0 that backporting isn't offered. Update to the
latest tag (`git pull` + the kit's update mode, or a fresh `init`) before
reporting, in case the issue is already fixed.

At 1.0, this section will be revised alongside the compatibility contract
described in [README.md → "What 1.0 promises"](README.md#what-10-promises).

## Disclosure

Coordinated disclosure: please give a reasonable window to investigate and
ship a fix before any public writeup. Credit is offered by default in the
fix's changelog entry unless you ask to stay anonymous.
