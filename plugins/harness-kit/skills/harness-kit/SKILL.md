---
name: harness-kit
description: >-
    Engineers and continuously improves reliable coding-agent behavior across
    Claude Code, Cursor, Codex, OpenCode, and .agents: canonical project
    context, executable quality gates, in-turn feedback, layered guardrails,
    local outcome telemetry, doc gardening, and CI-backed integrity. Includes
    generated provider stubs,
    shared permissions, an app-only development-runtime and live-verification
    workflow, optional execution profiles, and an authored devcontainer
    contract. Activates when asked to instrument, set up, standardize, or audit
    an agent/AI harness; improve recurring agent failures; add a skill,
    subagent, hook, guardrail, or verification gate; sync provider stubs; or
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
  secret-file patterns, existing agent config, and whether this is a runnable
  application. For apps, propose boot/readiness/seed/port/log/trace mappings
  from manifests, Compose, and Procfiles, present the classification/map, and
  require explicit runtime-adoption confirmation. If a partial harness exists,
  gap-fill — never overwrite hand-written content; migrate it toward `docs/`.
- **Runtime is conditional.** Only detected app repos get an authored,
  executable, manifest-pinned `scripts/dev.sh` plus tailored
  `dev-runtime`/`verify-live` docs, AGENTS links, and generated skill stubs.
  Non-app repos report runtime support as N/A; there is no generic `dev.sh`
  template.
- **Local outcomes are versioned and private by default.** Fresh installs get
  the self-contained `outcome-telemetry` convention and the model-free mixed-log
  reducer. Keep provider telemetry separate. Offer the canonical `doc-garden`
  skill as an explicit content choice; its default is an offline report, not a
  mutation or publication workflow.
- **Execution profiles are a separate explicit opt-in.** Declare only the
  confirmed provider subset in `EXECUTION_PROFILE_PROVIDERS`; unset/empty means
  unadopted. Merge provider tuples without clobbering hooks, permissions, MCP,
  or local keys, and name provider limits. Install the self-contained combined
  execution-profiles/devcontainer convention after at least one profile is
  adopted or the devcontainer is separately adopted. Claude's credentials
  tuple needs Claude Code 2.1.187 or later; declared Codex validation
  conditionally needs Python 3.11+ `tomllib` to parse the complete TOML file.
- **A devcontainer is authored, never placeholder-copied.** Offer it only from
  a confirmed image/Dockerfile/Compose source and a separate opt-in; non-root,
  no host credentials/socket mounts, no automatic repo-code lifecycle command,
  and build verification are required. Devcontainer-only adoption still gets
  the combined convention and its AGENTS link; it does not add a provider
  declaration.
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
- **Use `scripts/audit-log.sh` for outcome arithmetic.** Report its mixed-version
  data quality, gate/retry, repeated-deny, and review-count results; report
  session-trailer status/items, eval drift, and explicit N/A states. Inspect
  oldest baseline age separately; never manufacture plan cycles or PR
  attribution from prose.
- **Grade declared execution profiles provider-by-provider** as adopted,
  drifted, unavailable, or unverifiable; unset/empty is unadopted. Keep the
  provider observability availability table separate from
  `.harness/log.jsonl`, and audit devcontainer files statically unless the user
  separately authorizes a build/run verification. Require the combined
  convention/link for an adopted profile or devcontainer, while treating a
  merely pre-existing devcontainer as an offerable, unadopted boundary.
- **App runtime audit is read-only.** Invoke only `scripts/dev.sh health` after
  it is executable and manifest-pinned; classify missing, non-executable,
  unpinned, invalid JSON, stopped, unhealthy, or ready. Existing apps opt in to
  adoption; audit never starts, seeds, stops, or adds runtime content.
- **Offer to fix; don't fix unasked.**
- **Doc gardening is read-only by default.** Reuse `check-harness.sh`, then the
  offline `scripts/doc-garden.sh`; external probes, edits, commits, pushes, and
  PRs are separately authorized actions.

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
  configs, `.cursor/sandbox.json`, or `.devcontainer/*`).
- **Run the NEW kit's `templates/scripts/install-lib.sh`**, not the target's
  old copy, so update discovers mechanism files introduced by the new version.
  Runtime convention/skill/script adoption is a separate explicit opt-in for
  existing apps; execution profiles and a devcontainer are separate explicit
  opt-ins too; content is never auto-added or overwritten.
- **Outcome migration is split by ownership.** New reducer/scanner/log helpers
  and tests join the mechanism inventory; a pristine hook library can replace.
  `verify.sh` stays tailored policy, so v2 gate instrumentation is an approved
  diff. The telemetry convention, doc-garden skill, AGENTS links, and generated
  stubs remain opt-in content on an existing install.
- **Re-pin the manifest afterward** (preserving every ` # tailored` marker) and
  re-run `check-harness.sh` + hook tests. A real *standards* shift routes to
  [references/migrations.md](references/migrations.md), not improvisation.

## Rules that hold in every mode

- `docs/` is the single source of truth; never edit a generated stub by hand.
- Every guard hook gets a regression test wired into `check-harness.sh`.
- Hooks fail open; denial is exit 2; advisory stop-hooks never hard-block.
- `scripts/dev.sh`, where applicable, is tailored repo policy: pin and diff it,
  never replace it from a generic template or operate another worktree's app.
- An execution-profile declaration is never inferred from config presence;
  each declared provider must pass its accepted profile. Fixed stable tuples
  remain required except that Codex's network tuple may take the accepted
  experimental broad local/private-network compatibility disjunction. Name its
  broader reach and ownership-safe teardown limit. Never claim OpenCode permissions are an
  OS/network sandbox or Cursor repo config proves the effective UI/admin policy.
- Provider telemetry is not `.harness/log.jsonl`: the local stream accepts mixed
  exact-v1 and eight-key `version: 2` records, but ships no exporter endpoint,
  auth header, credential, real hostname, raw-prompt opt-in, provider import, or
  automatic cross-stream join. See the self-contained
  `templates/docs/conventions/outcome-telemetry.md` contract.
- Verify with the repo's own checks before declaring done, and report
  failures as failures.
