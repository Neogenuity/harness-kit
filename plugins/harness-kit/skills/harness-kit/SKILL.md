---
name: harness-kit
description: >-
    Scaffolds and maintains a standardized cross-agent harness (Claude Code,
    Cursor, Codex, OpenCode, .agents) in any repository: a canonical docs/
    knowledge base, an executable quality-gate runner (verify.sh), generated
    provider skill stubs, provider-agnostic hook scripts with lint feedback
    and observability logging, shared permissions, and a CI drift gate with
    mechanism integrity checks. Activates when asked to set up or
    standardize an agent/AI harness in a repo, audit an existing harness,
    add a skill/subagent/hook to the harness, sync provider stubs, or
    upgrade/migrate harness machinery ("harness init", "harness audit").
---

# Harness Kit

Installs and maintains the harness pattern in
[references/pattern.md](references/pattern.md): canonical content in `docs/`,
generated/thin provider shims, portable hooks, CI-gated drift checks. Provider
file locations and event mappings live in
[references/provider-matrix.md](references/provider-matrix.md).

Everything the kit installs is **vendored into the target repo** — never
reference files inside this skill directory from a target repo's configs.
Teammates without the kit (and non-Claude harnesses) must get identical
behavior from the repo alone.

**Pick a mode** from the user's request; default to `audit` when a harness
already exists and the request is vague. For **init** and **audit**, read
[references/pattern.md](references/pattern.md) first. Each mode's full playbook
lives in `references/modes/<mode>.md` — **read that file before executing the
mode.** The load-bearing invariants are inlined below so a quick task can't
misfire on the router alone, but the reference carries the steps.

## init — scaffold a repo → [references/modes/init.md](references/modes/init.md)

- **Recon before asking.** Detect stack, gate commands, providers, MCP servers,
  secret-file patterns, and existing agent config. If a partial harness exists,
  gap-fill — never overwrite hand-written content; migrate it toward `docs/`.
- **Author from the real codebase** (this is authoring, not copying templates),
  and **write the manifest AFTER tailoring** (step 8) so its checksums pin the
  tailored state.
- **`SECRET_PATTERNS` in `harness.conf` is the single source** for the secret
  guard — mirror it into every provider deny-list (`check-harness.sh` fails on a
  miss). Verify with `verify.sh` + `check-harness.sh` before declaring done.

## audit — grade an existing repo → [references/modes/audit.md](references/modes/audit.md)

- **Output a pattern-element → status table ordered by risk** (secret exposure
  first, drift second, missing content last), each row with its concrete fix.
- **Check the native permission deny-list mirrors the secret guard**, and report
  the MCP trust-inventory state, the governance docs, eval-bank health, and the
  age of the oldest `baselines.json` cell.
- **Offer to fix; don't fix unasked.**

## add-skill / add-agent / add-hook — extend → [references/modes/add.md](references/modes/add.md)

- **Author the canonical file in `docs/`**, link it from AGENTS.md, run
  `sync-agent-skills.sh`, and commit canonical + generated stubs together.
- **Every guard hook ships a `test-<name>.sh`** wired into `check-harness.sh` —
  a guard without a test is a future silent failure.
- **Sweat the frontmatter `description`** — it is the activation trigger.

## update — upgrade harness machinery → [references/modes/update.md](references/modes/update.md)

- **Checksum matches manifest → replace** with the new kit version; **differs,
  or the manifest line is ` # tailored` → diff only**, never auto-overwrite.
- **Never auto-overwrite policy files** (`verify.sh`, `format.sh`,
  `guard-secrets.sh`, `guard-project-policy.sh`, `harness.conf`, provider
  configs).
- **Re-pin the manifest afterward** (preserving every ` # tailored` marker) and
  re-run `check-harness.sh` + hook tests. A real *standards* shift routes to
  [references/migrations.md](references/migrations.md), not improvisation.

## Rules that hold in every mode

- `docs/` is the single source of truth; never edit a generated stub by hand.
- Every guard hook gets a regression test wired into `check-harness.sh`.
- Hooks fail open; denial is exit 2; advisory stop-hooks never hard-block.
- Verify with the repo's own checks before declaring done, and report
  failures as failures.
