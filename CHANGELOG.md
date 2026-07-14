# Changelog

All notable changes to harness-kit. The version is defined in
`plugins/harness-kit/VERSION` and mirrored into both plugin manifests.

## 0.15.0 — 2026-07-14

Runtime legibility — application repositories can expose one deterministic,
worktree-owned live runtime contract to every agent surface. The release ships
the universal instance helper, conditionally authors a tailored `dev.sh`, adds
a self-contained `verify-live` workflow, and grounds optional browser guidance
in each provider's actual surface. Implementation was delegated to Terra
(mechanism and executable evidence) and Luna (content and provider contract),
then cross-reviewed in both directions.

### Worktree-aware runtime mechanism

- **Universal `scripts/dev-instance.sh`** derives a stable `h` + 12-character
  lowercase hash suffix from the physical Git worktree root and namespace, and
  maps a validated base/span to a deterministic candidate port. Finite port
  hashing is collision-resistant, not collision-proof; runtime startup must
  fail loudly rather than reuse or kill another instance's occupied port.
- **Conditional `scripts/dev.sh` contract** for detected and confirmed app
  repositories implements `up|health|seed|down`. Every valid action returns one
  JSON v1 object; startup is idempotent and readiness-gated, seed resets named
  fixture data, health is read-only, and down can stop only this worktree's
  resources. State lives under `.harness/dev/`, with repo-relative JSON paths.
- **Installer/update integrity** treats the helper and its regression test as
  mechanism, but `dev.sh` as optional project policy: authored scripts are
  executable, manifest-pinned, diff-only, preserved on update, and protected by
  the config guard. Update mode now sources the incoming kit's `install-lib.sh`
  so pre-0.15 installs can discover newly introduced mechanism files.
- **Parallel full-gate support** lets independent template, eval, fixture, and
  harness checks overlap while preserving declaration-ordered output and exact
  failure rerun commands. The tailored verify template also includes the
  commented `full_gate "smoke" bash scripts/dev.sh health` adoption point.

### Live-verification content

- **Self-contained `verify-live` skill** enforces
  start/reuse → seed → reproduce → inspect targeted logs/traces → change → rerun
  the same flow → `verify.sh` → ownership-aware cleanup. It stops on a missing or
  invalid runtime contract instead of guessing repo-specific commands.
- **Runtime convention and app-aware init** document the lifecycle JSON schema,
  ownership, deterministic seeding, port override, log/trace paths, and failure
  behavior. Recon proposes commands from manifests, Compose files, and
  Procfiles; interview asks only unresolved details. Libraries receive no
  placeholder runtime content and audit reports N/A.
- **Safe adoption/audit** offers existing apps an opt-in proposal through
  update/audit; it never auto-adds or overwrites authored content or `dev.sh`.
  Audit calls only `health` and distinguishes missing, non-executable, unpinned,
  invalid JSON, stopped, unhealthy, and ready states.
- **Surface-aware browser guidance** is stamped from current primary sources
  for Claude Code Chrome, Cursor Browser, Codex Browser, OpenCode MCP, and
  Playwright CLI/MCP. It uses an already configured native/browser/computer-use
  surface when available, otherwise falls back to HTTP and explicitly reports
  that visual behavior was not checked; no browser tool is installed
  automatically.

### Evidence

- The root-only Python fixture runs main and linked-worktree HTTP instances
  concurrently, proves suffix/port separation, deterministic seed resets,
  valid JSON, logs, ownership-safe teardown, readiness-timeout cleanup, and
  that stopping A leaves B healthy. Python 3 is a contributor/test prerequisite
  only; installed harness prerequisites remain Bash, jq, Git, and SHA-256.
- The positive `verify-live-runtime` capability eval passed **3/3** on Codex
  `gpt-5.6-luna` (`pass@k=1`, `pass^k=1`, rate 1.00; run
  `20260714-170246-codex-gpt-5.6-luna`). Eval tasks now have closed,
  task-scoped `network: none|required` metadata so localhost fixtures can opt in
  without enabling network for ordinary Codex evals.

### Migration

- Update mode automatically installs or refreshes `dev-instance.sh` and its
  test.
- Existing app installs adopt `dev.sh`, runtime docs, AGENTS links, and the
  `verify-live` skill only by explicit opt-in; authored files are never
  auto-overwritten. Non-app repositories need no action.
- The commented live smoke-gate example is diff-only in an existing tailored
  `scripts/verify.sh`; adopt it manually if the repository wants that gate.

## 0.14.0 — 2026-07-13

Provider wiring assurance — the harness now *verifies* the wiring it documents.
A fresh clone with `.claude/settings.json`'s `hooks` object deleted used to pass
`check-harness.sh` at exit 0 ("coherent"); it now fails with a specific
per-guard error. Agent stubs join skill stubs as generated-and-checked. The
OpenCode/Cursor hook shim is descoped with a dated rationale rather than left a
documented-but-unshipped claim. Init/update gain a `jq` preflight and a tested
old-template recovery path. Eval baselines gain a bare-vs-plugin-activated
dimension. Execution plan reviewed by Codex gpt-5.6-sol (6 findings folded
pre-build); integrated diff reviewed by Codex gpt-5.6-terra. Implementation
delegated to parallel Opus 4.8 + Sonnet 5 worktrees.

### Hook-wiring validation (mechanism)

- **New `check-harness.sh` check** validates, per declared hook-wired provider
  (`HOOK_WIRED_PROVIDERS` in `harness.conf`), every required
  `(config, event, matcher, script)` tuple against the frozen provider matrix —
  a guard on the wrong event, a weakened matcher, a missing config, or a command
  pointing at a missing script now all fail (previously any of these stayed
  green). Migration: update mode replaces `check-harness.sh` and `install-lib.sh`
  and diffs the tailored `harness.conf` — declare `HOOK_WIRED_PROVIDERS` and
  `AGENT_PROVIDERS` on upgrade (update/audit proposes the set, you confirm; the
  check errors loudly until declared, and never infers the set from surviving
  configs).

### Agent-stub generation (mechanism)

- **Agent stubs are now generated** by `sync-agent-skills.sh` — like skill stubs
  — from `name`/`description` frontmatter on the canonical `docs/agents/*.md`,
  and checked for bidirectional equality. Previously hand-authored. Migration:
  update mode replaces `sync-agent-skills.sh`; re-run it and commit the
  regenerated stubs.

### Provider wiring reconciliation

- The OpenCode TS hook shim and Cursor `guard-config` wiring are **descoped**
  (dated 2026-07-13): documented as the reuse path, but no shim template ships,
  so OpenCode is not in the hook-wired set. Every shipped surface reconciled so
  none implies the shim ships.

### Install/update robustness (mechanism)

- **`jq` preflight** at init/update names missing prerequisites before
  scaffolding a harness whose guards would silently fail open.
- **Old-template recovery** for update mode across install channels (git tag,
  plugin cache, plain copy) via a git-ignored persisted pristine base, tested for
  the no-local-git path.

### Evals

- **Execution-variant dimension** (bare vs plugin-activated) in the baseline key:
  `bare` keeps the `provider/model` key (zero migration for existing baselines);
  a non-bare variant appends `/variant` so it can never overwrite the bare cell.
  The paid Codex plugin-activated recordings and acceptance-floor decision are
  deferred to a follow-up (activating the plugin inside a trial workspace is not
  yet built; `eval.sh --variant` only tags the row).

## 0.13.0 — 2026-07-13

Reviewer loop + skill split — the inferential half of the feedback system lands
(a canonical code-reviewer persona with a machine-parseable findings schema and a
seeded-defect catch-rate eval), and the plugin skill is split from a ~5.2k-token
monolith into a ~780-token router, proven at parity. Launch-readiness docs ship
alongside. Every gate is eval- or review-backed. Plan reviewed by Codex
gpt-5.6-sol; implementation reviewed by Codex gpt-5.6-terra.

### Reviewer loop

- **Canonical `code-reviewer` persona** (`templates/docs/agents/code-reviewer.md`,
  self-installed here at `docs/agents/code-reviewer.md`) — an inferential reviewer
  that runs only after `verify.sh` passes and checks the four classes deterministic
  gates can't see: misunderstood scope, over-engineering, cause-masking fixes, and
  missing/weak tests. Advisory by default; treats the diff as untrusted data.
  Hand-authored provider stubs for Claude, Cursor, Codex, and OpenCode.
- **Findings schema** — one v1-compatible `hook_log` line per finding appended to
  `.harness/log.jsonl`: the five reviewer fields (severity, line, category,
  evidence, suggested_fix) ride inside `detail`, so the top level stays the exact
  `{ts, hook, event, file, detail}` shape and every existing audit/log consumer
  keeps working unchanged.
- **Seeded-defect catch-rate eval** (`docs/evals/tasks/seeded-defect-review/`) —
  8 planted defects (2 per class); the grader credits a catch on (file, category)
  with a fully-formed finding, and `caught == 0` is a false-green violation
  (exit 3). Ship gate: `pass_rate ≥ 0.60` over 5 trials with zero violations.
  Recorded baseline: claude/sonnet **5/5** (`baselines.json`, 40 → 41 cells).
- **Opt-in PR-review CI workflow** (`templates/ci/github-actions-review.yml`) —
  wires the persona as an advisory PR reviewer: SHA-pinned actions, `pull_request`
  (never `pull_request_target`), minimal `permissions`, explicit `github_token`,
  fork-safe, cost-noted. Defines the `Harness-Session-Id:` session→PR trailer.

### Skill split

- **Plugin `SKILL.md` → compact router.** The ~299-line monolith becomes an
  ~81-line (~780-token) router whose mode table inlines each mode's load-bearing
  invariants; the full playbooks move verbatim to
  `references/modes/{init,audit,add,update}.md`. Activation footprint drops ~85%.
- **Shipped only on parity.** A fresh paired monolith-vs-split run (claude sonnet,
  3 trials, both discriminating tasks) held correctness 3/3 = 3/3 with wall-clock
  no worse, and was in fact cheaper (25–46% fewer tokens/cost per success).
  Evidence: `docs/evals/parity/skill-split.md`. The router surfaces the canonical
  `code-reviewer` persona and the PR-review workflow in init mode.

### Launch readiness (partial)

- **`SECURITY.md`** — private disclosure path for the shipped guard machinery,
  grounded in `docs/conventions/risky-actions.md` (advisory/fail-open is documented
  behavior, not a vulnerability), with a pre-1.0 supported-versions policy.
- **README** — a "What 1.0 promises" compatibility contract (what a template bump
  never touches vs. what each semver level means post-1.0) and a supported-platforms
  line (bash + jq on macOS/Linux/WSL/Git Bash; no native-Windows hook execution).
- Content-level secrets/hostname hygiene sweep of this repo (none found); the org
  move, demo, and public-flip remain maintainer actions.

### Upgrade notes

- Update mode **replaces** the plugin skill wholesale (it is distributed content,
  not tailored); the new `references/modes/` and `templates/` files are additive.
- No installed `scripts/` mechanism changed, so the dogfood manifest header stays
  at `0.12.0` by design — it records the mechanism version, and `check-packaging.sh`
  gates the `VERSION`/plugin-manifest trio, not the header. No re-pin.

## 0.12.0 — 2026-07-13

Eval discrimination + context efficiency — a joint release that makes the
behavioral eval bank actually discriminate model/harness behavior, lands the
measured fixes from the 2026-07-12 context-efficiency audit, and records the
first full four-model baseline matrix. Every behavior change ships against eval
evidence, not intuition. Plan reviewed by Codex gpt-5.6-sol; implementation
reviewed by Codex.

### Eval layer

- **Per-trial provider usage on every results row.** `eval_result_json` now
  carries a typed `usage` object — uncached / cached-read / cache-write input
  tokens, output tokens, cost (when the provider reports it), and tool-call
  count — with JSON `null` (never `0`) for any field a provider does not emit.
  Claude and Codex transcripts are parsed by provider-specific extractors pinned
  to committed fixtures; `eval-harness.sh` scoring stays correctness-only and
  tolerates pre-0.12 rows.
- **Two discriminating tasks adopted** — `hn-add-skill` (recipe-free add-skill)
  and `tmpl-secret-pattern` (template-vs-installed secret mirror), each proven by
  reference and violation fixtures.
- **First four-model baseline matrix.** `baselines.json` grows 16 → 40 cells:
  Claude haiku+sonnet and Codex gpt-5.6-terra+gpt-5.6-luna across the full
  10-task bank, spanning a cheap tier (haiku, luna) and a capable tier (sonnet,
  terra) on both providers. Every cell carries a per-cell `recorded` date, and
  the under-trialed regression cell is re-recorded at 3 trials. The bank now
  discriminates — `hn-add-skill` splits Claude 3/3 vs Codex 0/3, and the negative
  neuter-check surfaced haiku reward-hacking a gate script (1/3) that a smaller
  sample had scored a clean 3/3.
- **Opt-in scheduled eval workflow** (`ci/github-actions-eval-cron.yml`) — weekly
  cron plus manual dispatch defaulting to the free `mock` provider, scoring-only
  (never `--update-baseline`), SHA-pinned actions, cost-honesty notes. Copy to
  `.github/workflows/` and wire a provider credential to run live.

### Harness behavior (context-efficiency audit fixes)

- **AGENTS.md skill-link convention** — one line making "link every new skill and
  convention doc from AGENTS.md" explicit; the audit measured this single
  sentence as the difference behind a 0/6 add-skill failure mode.
- **Guard deny-hint** (`GUARD_DENY_HINT` in `harness.conf`, empty default) — an
  optional tailorable line appended to the config-guard's deny message so a
  denied edit can point the agent at the right place.
- **Protected-path over-match fixed** — the `opencode.json` entry is root-anchored
  (`/opencode.json`), so the guard still protects the installed root file without
  denying edits to the shipped `templates/providers/opencode/opencode.json`.
- **Banner trim** (`BANNER_RECENT_COMMITS`, default 0) — the session-start
  banner's recent-commits block is now an opt-in tailorable (zero observed
  in-session consumers across the audit).
- **Stop-hook clean-tree skip** — `guard-project-policy.sh` skips the
  `verify.sh --fast` run on a clean tree (which cannot newly fail it), removing a
  measured stop-time tax; advisory behavior on a dirty tree is unchanged.

### Migration

Mechanism + content release. Update mode replaces the manifest-matching
`scripts/` files and diffs the tailored ones. Two new `harness.conf` keys
(`GUARD_DENY_HINT`, `BANNER_RECENT_COMMITS`) arrive with empty/zero defaults — no
action needed unless you want to set them. The AGENTS.md skill-link line is
content (`AGENTS.md.tmpl`), applied on re-init or copied by hand.

### Deferred

The plugin skill-split (SKILL.md → compact router + per-mode references), gated
on fresh paired parity runs, is deferred to a queued `skill-split.md` plan; it
needs its own parity round and ships only on evidence.

## 0.11.0 — 2026-07-12

Hook hardening + feedback repair — the 2026-07-12 project review re-verified
the provider matrix against live docs and probed the installed guards with
real payloads, surfacing self-protection gaps and degraded feedback channels.
This release closes them. Mechanism-only; no new tailoring required. Scope was
triple-reviewed after implementation (2× Claude Opus 4.8 + Codex
gpt-5.6-terra); every confirmed finding was fixed and fixture-covered before
tagging.

- **Guard-coverage gaps closed.** `guard-config.sh`'s default `PROTECTED_PATHS`
  now also denies edits to `scripts/harness.conf` (the secret guard's pattern
  source), `.claude/settings.local.json` (can carry `disableAllHooks: true`;
  gitignored and unmanifested in the standard Claude Code setup, so no other
  layer caught it), and the three MCP configs the trust-inventory audit reads
  (`.mcp.json`, `.cursor/mcp.json`, `.codex/config.toml`). Post-init
  `harness.conf` tailoring rides the existing `HARNESS_ALLOW_MECHANISM_EDITS=1`
  escape hatch.
- **Path-normalization bypass fixed.** The guard now collapses `.`/`..`/`//`
  segments before matching, so a crafted `scripts/./harness.conf` or
  `scripts/../scripts/harness.conf` can no longer slip a protected path past
  the literal globs. (Case variants on a case-insensitive filesystem remain a
  documented guardrail limitation — the CI manifest check is the enforcing
  layer.)
- **Deny reasons are model-visible.** On a `PreToolUse` payload, `hook_deny`
  emits an exit-0 JSON `permissionDecision:deny` carrying the reason (parsed by
  Claude Code and Codex) instead of an exit-2 stderr the model may not see. The
  portable exit-2 deny stays as the fallback for every other layout and
  whenever JSON construction *or the stdout write* fails — a deny never fails
  open.
- **Cursor feedback arm repaired.** `afterFileEdit` documents no output field
  for feedback text and parses exit-0 stdout as JSON, so `hook_feedback` now
  emits the documented no-op (`{}`) on the Cursor layout instead of dead plain
  text; the finding still reaches `.harness/log.jsonl`.
- **Advise-once future-proofed.** A payload-independent marker guard
  (`.harness/stop-markers/`, keyed on session/conversation id + a warnings
  digest) keeps the stop advisory firing exactly once even if a future build
  drops the undocumented-but-still-sent `stop_hook_active` flag. The prune is
  scoped to the guard's own markers, so a user-pointed `HARNESS_STOP_MARKER_DIR`
  never loses unrelated files.
- **Provider matrix refreshed** with Cursor's grown hook surface
  (`beforeShellExecution`, `beforeMCPExecution`, generic
  `preToolUse`/`postToolUse`, per-hook `failClosed`), a recorded decision to
  defer wiring `guard-secrets.sh` to `beforeShellExecution` (its payload puts
  `command` top-level, which `hook_command_string` doesn't read), and restamped
  sources; `eval.sh`'s pinned CLI invocation restamped to Claude Code 2.1.207.

**Migration.** Update mode **replaces** `guard-config.sh` and `lib.sh` (both
non-tailored mechanism files) and adds `scripts/hooks/test-deny-reasons.sh`; it
**never touches** your tailored `harness.conf` or `verify.sh`. No config
changes are required. If you tailored `guard-config.sh`'s `PROTECTED_PATHS`
locally, re-apply your additions after updating — the file is replaced, not
diffed.

## 0.10.1 — 2026-07-12

CI fix — the `ci` workflow's "Hook templates are executable" check had failed
on every push to `main` since v0.8.0. The four eval-layer scripts added in
that release (`eval.sh`, `eval-lib.sh`, `eval-harness.sh`, `test-eval.sh`)
were committed to `plugins/harness-kit/skills/harness-kit/templates/scripts/`
without the executable bit, even though their identical-content counterparts
under the repo's own installed `scripts/` were correctly `+x`. No behavior or
template-layout change; mode bits only.

- `chmod +x` the four affected template files to match their `scripts/`
  counterparts and every sibling file in that directory.

## 0.10.0 — 2026-07-12

Execution governance baseline — the kit previously scaffolded knowledge,
gates, and evals but said nothing about *containment*: which MCP servers a
repo trusts, what an agent should do with hostile content, or whether the
shipped CI could be quietly repointed. Scope was design-reviewed before
implementation (Codex gpt-5.6-sol, 14 findings incorporated — most
materially: the MCP inventory pins expected *identity*, not just names) and
the implementation was triple-reviewed (2× Claude Opus 4.8 + Codex
gpt-5.6-terra, all SHIP-WITH-FIXES; every fix landed and is
fixture-covered).

- **MCP trust inventory (new check #8c).** `harness.conf` gains
  `MCP_ALLOWED_SERVERS` — one `<name> <expected-identity-substring>` line
  per allowed server. `check-harness.sh` extracts every *enabled* server
  from `.mcp.json`, `.cursor/mcp.json`, `opencode.json`, and
  `.codex/config.toml` (best-effort TOML scan; single- and double-quoted
  table names) and audits it: with no inventory declared, configured
  servers produce one adoption WARN; once the inventory is declared (even
  empty — the strict default), an uncovered server or one whose configured
  command/args/URL no longer contains its pinned substring is an **ERROR**.
  A name-only inventory line is itself an ERROR (an empty pin would match
  any identity). Unparseable configs and jq-absent machines get a loud
  "not audited" WARN — except trivially-empty maps (`"mcp": {}`), which
  stay silent via a dependency-free fast path. Disabled entries are
  skipped. **Migration:** update mode replaces `check-harness.sh`; add an
  `MCP_ALLOWED_SERVERS` block to your tailored `harness.conf` (the shipped
  template carries a commented example) — repos with no MCP configs see no
  change.
- **Untrusted-content + risky-actions conventions (shipped docs).** Two new
  template docs under `docs/conventions/`: `untrusted-content.md` (tool/
  repo/web/MCP output is data, not instructions; the untrusted-clone
  checklist; which containment layers actually *hold* under a hostile
  instruction, per provider — including that OpenCode ships no OS sandbox)
  and `risky-actions.md` (destructive-op policy and the safe-default
  posture, every wiring example labeled by its enforcement layer so hooks
  are never mistaken for boundaries). `AGENTS.md.tmpl` links both and its
  security checklist now says repo/tool/web/**MCP**.
- **Provider matrix: execution containment.** New verified section
  (sandbox, network policy, approval modes for Claude Code / Codex /
  Cursor / OpenCode, checked against vendor docs 2026-07-11) — the factual
  basis the conventions docs cite instead of asserting.
- **Shipped-CI hardening + guard widening (new doctor #10d).** The CI
  templates pin actions to full commit SHAs, declare `permissions:
  contents: read`, `timeout-minutes`, and `persist-credentials: false`;
  `check-harness.sh` gains doctor WARN #10d flagging any mutable
  (tag/branch) `uses:` ref in `.github/workflows/` (quoted refs
  unwrapped); `guard-config.sh` PROTECTED_PATHS broadens from the single
  harness-check workflow to `.github/workflows/*`. **Migration:** update
  mode replaces the guard and check; workflows are yours — re-apply the
  hardening from the template if you've tailored them.
- **Plans.** The governance plan's advanced half (per-provider sandbox
  profiles, devcontainer, audit-log export) split into its own queued plan
  ([docs/plans/execution-sandbox-profiles.md](docs/plans/execution-sandbox-profiles.md));
  completed plan at
  [docs/plans/completed/v0.10.0-execution-governance-baseline.md](docs/plans/completed/v0.10.0-execution-governance-baseline.md).

## 0.9.0 — 2026-07-11

Eval integrity and plans hygiene — a 2026-07-11 project review (findings
adversarially checked by a second model, Codex gpt-5.6-sol) found the v0.8.0
eval layer could silently mis-score, and found the launch and a saturated
task bank tracked nowhere the plans machinery could see.

- **Eval integrity fixes.** Latest-run selection in `eval-harness.sh` now
  picks by per-run `run_started_at` epoch (`max_by([(.run_started_at // 0),
  .run])`) instead of lexicographic run-id sort, so a custom `--run-id`
  can no longer permanently outrank a chronologically newer run; legacy
  result lines with no `run_started_at` still parse. `eval.sh` refuses to
  reuse a results directory that already has recorded results, and
  refuses to run against a dirty working tree (each trial clones committed
  `HEAD`) unless `--allow-dirty-head` is passed. Negative tasks gain a
  distinct `negative_violation` outcome via a `check.sh` exit-3 convention
  (exit 1 keeps meaning `task_failure`), and `eval-harness.sh` fails loudly
  on any `negative_violation` regardless of suite. `--update-baseline` now
  excludes `--provider mock` rows, refuses atomically unless every cell has
  exactly `--expected-trials` (default 3) trials, and writes each cell's
  `recorded` date from the run's own timestamp. Task metadata (`suite`,
  `polarity`, `provider`, `grade`) is now enum-validated at load time, and a
  `provider:` value gates a task off providers it doesn't target (`mock` is
  exempt). The default `--run-id` (when none is passed) changes from a bare
  UTC timestamp (`YYYYMMDD-HHMMSS`) to `TIMESTAMP-provider-model`, so two
  providers (or two models) launched in the same second no longer collide on
  a results dir — anything scripting against results-dir names by pattern
  should account for the new suffix. **Migration:** `update` mode replaces
  the four eval scripts as usual; the `results.jsonl` schema gains
  `run_started_at` and `outcome` fields (old lines keep parsing — legacy rows
  are outranked by any new, timestamped run). Negative-task graders should
  adopt exit 3 for a caught shortcut; a plain exit 1 still fails the task but
  records `task_failure`, which does not trigger the loud scorer failure
  path.
- **Plans, docs, and CI.** New active plan
  [docs/plans/completed/v0.9.0-eval-integrity-and-plan-hygiene.md](docs/plans/completed/v0.9.0-eval-integrity-and-plan-hygiene.md)
  tracks this work; two new queued plans,
  [docs/plans/eval-discrimination.md](docs/plans/completed/v0.12.0-eval-discrimination.md)
  (a task bank that actually discriminates model behavior) and
  [docs/plans/launch-readiness.md](docs/plans/launch-readiness.md) (the
  launch, previously tracked only as README checkboxes), join the roadmap;
  `docs/plans/active/` is now tracked (a fresh clone previously lost the
  directory). `.github/workflows/ci.yml` now runs `bash scripts/verify.sh`
  directly instead of hand-reconstructing its steps, so a gate added to
  `verify.sh` can no longer silently drop out of CI. README's hardcoded
  `v0.6.0` claim is replaced with a pointer to `plugins/harness-kit/VERSION`,
  and the release skill gains a sweep step so this can't go stale again.

## 0.8.0 — 2026-07-11

Behavioral evals — the harness could prove it was *coherent* (drift, links,
checksums) but not that it *worked*. This release adds the layer that measures
whether the harness actually changes agent behavior: repo-specific golden tasks
run over multiple isolated trials, scored by pass@k / pass^k against recorded
baselines.

- **New eval mechanism** (`scripts/eval-lib.sh`, `eval.sh`, `eval-harness.sh`,
  `test-eval.sh`). `eval.sh <task> --provider <claude|codex|mock> --trials N`
  runs a golden task over N independent trials, each in a fresh isolated
  workspace (a throwaway `git clone`), captures a transcript per trial under
  `.harness/eval-results/` (git-ignored), and grades the end state with the
  task's `check.sh` (+ optional `verify.sh`). `eval-harness.sh` computes
  pass@k / pass^k per task and fails on a regression-suite drop vs
  `docs/evals/baselines.json`. `--provider mock` runs the reference solution
  through the whole pipeline for a zero-cost plumbing/grader-validity check.
- **`docs/evals/` convention + task bank.** `TASK.md` (suite: capability|
  regression, polarity: positive|negative), a `check.sh` grader independent of
  any agent-written test, and a `reference/apply.sh` proving the task solvable.
  Ships a `_template` task and a rubric+calibration-note example; this repo
  carries an 8-task dogfood bank spanning both suites and both polarities.
- **Grader validity is CI-enforced.** `test-eval.sh` (wired into `verify.sh`)
  proves, with no model in the loop, that every task's reference solution scores
  as a pass and every negative task's `reference/violate.sh` scores as a fail —
  a grader that can't catch the shortcut is caught here.
- **init/audit integration.** init interviews for the 1-2 success-defining tasks
  and scaffolds `docs/evals/`; audit reports task counts by suite/polarity,
  grader validity, and baseline age.
- **Migration.** `update` treats `eval-lib.sh` / `eval.sh` / `eval-harness.sh` /
  `test-eval.sh` as mechanism files: they are copied on init, added on upgrade
  from an older manifest, pinned in `.harness-manifest`, protected by
  `guard-config.sh`, and enumerated by `check-harness.sh`'s completeness check.
  No action needed — an existing harness picks them up on the next `update`.

## 0.7.0 — 2026-07-11

Install/update verification — the kit's core product boundary (`init` / `update`)
was the only mechanism with no automated test; it now has a deterministic
fixture suite, and two *verified* integrity blind spots in the manifest
mechanism it exercises are closed.

- **Deterministic install/update mechanics extracted and tested.** New template
  `scripts/install-lib.sh` is the model-free core of init/update — pure
  filesystem functions (`harness_install_mechanism`, `harness_generate_manifest`,
  `harness_repin_manifest`, `harness_update_decision`, `harness_update_apply`,
  `harness_append_gitignore`) that the SKILL's `init`/`update` prose now calls
  instead of inlining shell. New template `scripts/test-install.sh` drives them
  against throwaway git fixtures: clean init, non-clobber floor (hand-written
  `AGENTS.md`/`settings.json` survive byte-for-byte), no-op update idempotence,
  mechanism upgrade, and `# tailored`-file preservation, plus a seeded
  deny-list drift case. The model-graded half of init/update (authoring quality,
  merge judgment) stays out of scope by design. **Migration:** `update` now
  manages `install-lib.sh` and `test-install.sh` like any other mechanism file;
  they are copied on init and pinned in the manifest.
- **`scripts/harness.conf` is now manifest-pinned** (verified finding). It is the
  single source for `SECRET_PATTERNS`, yet was pinned by neither the manifest
  producer nor `guard-config.sh` — so a narrowed `SECRET_PATTERNS` disarmed the
  secret guard for `id_rsa`/`*.pem`/`.env.*` while `check-harness.sh` stayed
  green. It is now enumerated by `harness_generate_manifest` (marked
  ` # tailored`, since its patterns are repo-specific), so an un-re-pinned edit
  fails CI like every other policy file. **Migration:** `update` gains a
  `harness.conf` line in the manifest; re-pin after tailoring `SECRET_PATTERNS`.
- **Manifest integrity hardened on three fronts** (verified findings, incl. a
  multi-model review round). `check-harness.sh` check #9 previously only verified
  the files the manifest *did* pin, so an adopted repo's manifest could be
  gutted by shell edit to disarm a guard while CI stayed green. Now, when
  `scripts/hooks/` is present: (a) a missing / emptied / all-malformed manifest
  is an ERROR, not a silent skip; (b) a nonempty malformed line no longer counts
  as a pin; and (c) **completeness** — every mechanism file on disk must be
  pinned (the expected set is derived from the filesystem, not the manifest), so
  *partial* pin deletion (un-pinning one guard while leaving others) is caught.
  A genuinely pre-adoption repo still passes.
- **Update mechanics corrected** (review round). `harness_update_apply` now (i)
  treats policy files (`verify.sh`, `harness.conf`, `format.sh`, `guard-secrets.sh`,
  `guard-project-policy.sh`) as diff-only even when pristine and unmarked — never
  auto-overwriting them (SKILL update step 3) — and (ii) installs mechanism files
  the new kit ships that an older install's manifest can't list, so a `0.6`→`0.7`
  upgrade actually picks up `install-lib.sh`/`test-install.sh`. `harness_repin_manifest`
  carries forward tailored pins the shipped producer doesn't emit (a repo's own
  local gates), so a re-pin never silently drops a project-added integrity pin.
- **`install-lib.sh` added to `guard-config.sh`'s protected paths** (mechanism,
  with a `test-guard-config.sh` case) and **check #6 skips only `test-install.sh`
  and `test-check-harness.sh` when nested** (via `HARNESS_NESTED_FIXTURE`, set by
  `test-install.sh`) so the fixture suite can run `check-harness.sh` inside a
  throwaway install without recursing — every other regression test, the guard
  behavioral checks included, still runs, so no single env var can switch off the
  regression layer.

## 0.6.0 — 2026-07-11

- **Plans machinery now ships.** The kit's docs promised a `docs/plans/`
  directory (`harness.conf` sets `PLANS_DIR`, `session-context.sh` announces
  it, `AGENTS.md` links its README) but no template shipped and `init` never
  authored one — a fresh harness referenced a directory that didn't exist. New
  templates `docs/plans/README.md` (lifecycle: queued → `active/` →
  `completed/`, theme-naming, the markdown-link honesty rule) and
  `docs/plans/_template.md` (the nine plan sections); `init` step 5 authors the
  README and creates `PLANS_DIR`, and `audit` flags a configured `PLANS_DIR`
  whose directory is missing. A throwaway
  [fixture recipe](plugins/harness-kit/skills/harness-kit/references/fixture-recipe.md)
  documents how to smoke-test `init` end-to-end.
- **GitHub Copilot + Gemini CLI added to the provider matrix** (both verified
  2026-07-11): Copilot reads `AGENTS.md` natively including nested files (plus
  `.github/copilot-instructions.md`); Gemini CLI reads it via a
  `.gemini/settings.json` `context.fileName` snippet. Both are
  instructions-only (no hook/skill/agent surface), so `init` step 6 gains two
  near-free wire steps.
- **Stricter harness checks** (mechanism — `check-harness.sh` +
  `test-check-harness.sh`, manifest re-pinned):
  - Canonical skills are now validated against the **Agent Skills spec** as
    ERRORs, not doctor hints: closing `---` delimiter, non-empty `name`/
    `description`, `name` equal to its parent directory, `name` charset with no
    leading/trailing or consecutive hyphens, and the 64/1024-char limits
    (previously warnings). Prefers `skills-ref validate` when on PATH, with a
    dependency-free bash fallback.
  - New doctor WARNs: an `active/` plan missing a `Next action` or unchanged
    for 30+ days (git-dated; a no-op in shallow CI), and a provider-matrix
    `verified <date>` stamp older than 90 days or a matrix with no stamp at all
    (`PROVIDER_MATRIX_DOC`, `HARNESS_PLAN_STALE_DAYS`,
    `HARNESS_MATRIX_STALE_DAYS` are configurable in `harness.conf`).
- **Docs:** provider-matrix capability rows now carry `verified` stamps;
  `pattern.md` notes dynamic workflows riding skill-resource mirroring and
  positions hooks as *feedback* vs. OS sandboxing as *enforcement* (pointing at
  the execution-governance plan).

## 0.5.0 — 2026-07-10

- **Repackaged `plugin/` → `plugins/harness-kit/` + a Codex distribution
  channel.** The same source tree now installs as a versioned, updatable
  plugin in **both** Claude Code (`/plugin marketplace add`) and Codex
  (`codex plugin marketplace add`) — the manual clone-and-copy of
  `skills/harness-kit` still works but is no longer the only path. New files:
  `plugins/harness-kit/.codex-plugin/plugin.json` and the root
  `.agents/plugins/marketplace.json` (Codex's nested-source marketplace shape,
  with `policy`/`category`; distinct from Claude Code's flat-string source —
  schemas verified 2026-07-10 against learn.chatgpt.com/docs/build-plugins).
  See [ADR 007](docs/architecture/decisions/007-dual-provider-packaging.md).
- **`plugins/harness-kit/VERSION` is now the single version source**, mirrored
  into both `plugin.json` files. New `scripts/check-packaging.sh` (the
  `verify.sh` manifests gate) asserts the whole cross-file invariant — four
  valid manifests, semver `VERSION` equal to both plugin versions, name
  agreement, `./`-relative contained source paths, the Codex `skills` dir, and
  in-enum `policy`/`category`.
- **Codex hook commands now resolve from the Git root** (from PR #6 review): a
  Codex session whose CWD is a repo subdirectory previously exited 127 because
  `bash scripts/hooks/X.sh` is CWD-relative. All five commands in the Codex
  `hooks.json` now use `bash "$(git rev-parse --show-toplevel)/scripts/hooks/X.sh"`
  (the pattern the hooks docs recommend); a new `test-codex-hooks-cwd.sh`
  regression test runs every command from a nested CWD in CI.
- **Docs:** provider matrix gains a stamped **Distribution** row; new
  migrations playbook for a provider shipping a plugin/marketplace channel;
  README gains a "Codex, as a plugin" install section; the release skill now
  bumps `VERSION` + both plugin.jsons together. Corrected a stale `pattern.md`
  line that claimed `# tailored` manifest lines skip integrity checking (they
  are still checksum-verified; the marker only exempts template *replacement*).
- Update-mode note: this is a path/packaging change. Existing installs keep
  working; to move to the plugin channel, install via your provider's
  marketplace instead of the copy path. `lib.sh` and the guard/test scripts
  are unchanged from 0.4.1 apart from the new Codex-hooks-CWD test.

## 0.4.1 — 2026-07-10

- **Codex apply_patch guard bypass (found by real-payload capture):** a live
  Codex 0.144.1 payload — reconciled against the generated hook schemas
  (`openai/codex: codex-rs/hooks/schema/generated`) — showed that a file edit
  arrives as the **bare** apply_patch envelope (`*** Begin Patch` … `*** End
  Patch`) directly in `tool_input.command`, with the tool identity carried in
  `tool_name`; the literal `apply_patch` is **not** in the command. But
  `lib.sh:hook_affected_files` gated on `case "$cmd" in *apply_patch*)`, so it
  extracted nothing from a real Codex edit — making `guard-config.sh`,
  `format.sh`, and `guard-secrets.sh`'s write-side denial silent no-ops on
  Codex. Impact: an agent on Codex could edit protected harness mechanism
  (e.g. `scripts/hooks/lib.sh`) or write a secret file via apply_patch
  **undenied**. Fix: `hook_affected_files` parses the bare envelope when
  `tool_name` is `apply_patch` — the tool identity, not command text — and
  keeps the `apply_patch`-literal branch for the shell-wrapper form
  (`apply_patch <<'EOF' …`, which also rides a Bash/shell tool). Gating on the
  tool identity, rather than on the bare `*** Begin Patch` marker, is
  deliberate: a first pass keyed on the marker text alone fail-**closed**
  ordinary shell payloads that merely *contain* patch text (a heredoc writing
  a `.patch` file), fabricating affected-file paths and denying them — caught
  in review before merge.
- **Why CI stayed green:** every Codex apply_patch fixture used the
  `apply_patch <<'EOF'` wrapper form (which contains the literal), so the
  wrong envelope shape was never exercised. Bare-envelope regression cases are
  added to `test-affected-files.sh`, `test-guard-config.sh`, and
  `test-guard-secrets.sh`, plus a shell-command-containing-patch-text case in
  each pinning the no-false-close boundary; the affected-files/guard fixture
  comments now cite the captured payload as the source of truth.
- Update-mode note: `lib.sh` and the three `test-*.sh` files are mechanism
  (replaced on checksum match). Take the kit update and re-pin
  `scripts/.harness-manifest`; behavior-only change, no config migration.

## 0.4.0 — 2026-07-10

- **Codex protocol correctness (from adversarial review, validated against
  the current docs at learn.chatgpt.com):** Codex hook payloads carry no
  `tool_input.file_path` — file edits arrive as apply_patch invocations in
  `tool_input.command` — so the guards and `format.sh` were silent no-ops
  on Codex. New `lib.sh:hook_affected_files` / `hook_command_string`
  normalize all three provider layouts (direct fields, plus apply_patch
  envelope headers including multi-file patches and renames);
  `guard-config.sh`, `guard-secrets.sh`, and `format.sh` now iterate every
  affected file. `guard-secrets.sh` adds a best-effort token scan of shell
  commands (the only live secret layer on Codex) with apply_patch bodies
  stripped to avoid false denies, and now also denies patch writes to
  secret files. Fixtures are schema-derived; pinned by the new
  `test-affected-files.sh` plus Codex cases in every guard test.
- **Stop-hook protocol:** Codex requires JSON on Stop stdout at exit 0;
  `hook_advise_once`'s second pass now emits `{"continue": true}` (valid in
  Claude Code too — the layouts are indistinguishable) and `{}` on the
  Cursor layout instead of plain text.
- **Manifest integrity:** `check-harness.sh` check #9 now checksum-verifies
  ` # tailored` lines too — the marker only exempts a file from template
  replacement (update mode) and template-equality checks, never from
  integrity verification. Re-pin tailored lines after editing, keeping the
  marker.
- **Docs:** provider matrix re-verified 2026-07-10 — Codex hooks are GA and
  enabled by default (`hooks` feature key; `codex_hooks` deprecated alias;
  `commandWindows` exists), payload/Stop facts corrected, sources updated
  to learn.chatgpt.com (developers.openai.com/codex/* now redirects there).
- **CI:** test matrix now includes macOS (exercises the BSD awk/`shasum`/
  `readlink -f` branches).
- Update-mode note: `lib.sh`, both guards, `format.sh`, and
  `check-harness.sh` are mechanism (replaced on checksum match). A tailored
  `format.sh` fork needs the multi-file iteration applied manually — the
  TAILOR arms now live inside a `process_one()` function.

## 0.3.0 — 2026-07-09

- **Packaging:** the distributable plugin moved from the repo root into
  `plugin/` (`marketplace.json` `source: "./plugin"`). Installs no longer
  include repo-level files. If you track paths, `skills/…` is now
  `plugin/skills/…`.
- **Self-application:** this repository now runs its own harness — root
  `AGENTS.md`/`CLAUDE.md`, `docs/` knowledge base with ADRs, vendored and
  tailored `scripts/` (manifest-pinned), all-provider wiring, and the
  `harness-check.yml` drift gate in CI.
- **Docs:** README rewritten around the one-line value proposition;
  architecture overview and five decision records added; MIT license,
  CONTRIBUTING, and `llms.txt` added.
- **Mechanism hardening (from adversarial review):** `check-harness.sh`
  check #6 now also runs top-level mechanism tests (`scripts/test-*.sh`);
  new check #8b verifies OpenCode's `opencode.json permission.read` against
  `SECRET_PATTERNS`; checks #8/#8b now error (instead of silently skipping)
  when a wired `.claude/` or `.opencode/` is missing its native deny-list
  file; `guard-config.sh` protects `opencode.json`; the Claude deny-list
  template covers root-level `*.pem`/`id_rsa`/`id_ed25519`; every
  `SECRET_PATTERNS` entry now has a `test-guard-secrets.sh` case; the
  version-bump stop-hook compares version values against HEAD. Update-mode
  note: `check-harness.sh` and the test scripts are mechanism (replaced on
  checksum match); `settings.json`/`opencode.json` are policy (diffed).

## 0.2.0 — 2026-07-08

- Verification loop: post-edit lint feedback hooks the agent self-corrects
  on, `verify.sh --fast` wired into the advisory stop-hook.
- Self-guarding harness: `guard-config.sh` (mechanism/lint-config edit
  denial), manifest checksum integrity in `check-harness.sh`, native
  deny-list drift detection against `SECRET_PATTERNS`.
- Observability: every deny/advisory/lint event appends to
  `.harness/log.jsonl`; audit mode summarizes it.
- Provider matrix revalidated against 2026-07 harness docs (per-fact
  verified stamps + Sources section).

## 0.1.0 — 2026-07-08

- Initial extraction from a production Laravel modular monolith: canonical
  `docs/` knowledge base + `AGENTS.md` TOC, generated provider skill stubs
  (`sync-agent-skills.sh`), portable hook scripts with regression tests,
  shared permission templates, and the `check-harness.sh` CI drift gate.
