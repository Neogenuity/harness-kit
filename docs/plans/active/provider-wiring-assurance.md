# Provider wiring assurance

Status: **active** — v0.14.0 (activated 2026-07-13)

## Objective

Close the gap between what the harness *documents* as wired and what any
check *verifies* is wired: semantic validation of per-provider hook configs,
agent-stub coherence driven by the already-declared `CANONICAL_AGENTS`,
the described-but-unshipped OpenCode/Cursor hook wiring, an explicit
runtime-prerequisite preflight at init, a tested old-template recovery path
for copied/plugin installs, and a recorded per-provider acceptance policy for
the eval cells the release process currently treats as informational.

## Value

A 2026-07-13 post-v0.13.0 cross-review (Codex gpt-5.6-sol; every claim
adopted below was independently re-verified in-repo before this plan was
scoped) found several runtime assurances weaker than the docs suggest. The
empirical anchor: in a fresh clone, deleting the entire `hooks` object from
`.claude/settings.json` leaves `bash scripts/check-harness.sh` exiting 0 —
"agent harness is coherent" with every Claude Code hook disabled (reproduced
2026-07-13). `guard-config.sh` denies *tool-mediated* edits to the provider
configs at runtime, but hook wiring has no CI enforcing layer at all: the
configs are deliberately not manifest-pinned (they are tailored policy —
byte-pinning them is wrong by design), and no check validates their
semantics — unlike the secret deny lists, which get exactly this treatment
in checks #8/#8b. The same claim-to-implementation pattern repeats across
the review's confirmed findings, and closing that class of gap has led the
roadmap's ordering rationale since v0.6.0.

## Scope

1. **Semantic hook-wiring validation** — a new `check-harness.sh` check
   built on per-provider required *tuples*, not mere presence: for each
   hook-wired provider, every tuple of (config path, event, matcher, script)
   from the provider matrix's hook table must hold — the guard attached to
   its correct event and matcher, the referenced command resolving to an
   existing executable script. "Events exist and some script resolves" is
   not enough: that would stay green after a guard is swapped onto the wrong
   event or a matcher is weakened. Which providers count as hook-wired must
   be *declared*, not inferred from directory presence (provider dirs also
   hold generated stubs, so a deleted `.cursor/hooks.json` would otherwise be
   indistinguishable from a provider that was never wired) — persist the
   selection at init (e.g. a `HOOK_WIRED_PROVIDERS` line in `harness.conf`);
   a declared provider with a missing config is an ERROR, mirroring check
   #8's posture for a deleted `settings.json`. Existing installations need a
   migration path, because `harness.conf` is tailored/diff-only during
   update and would never gain the declaration on its own — the check would
   otherwise validate *zero* providers on every upgraded pre-declaration
   install, leaving the headline hole open exactly where it ships today.
   Migration must be **explicit confirmation, never inference from surviving
   configs**: a config deleted *before* migration is mechanically
   indistinguishable from a provider never wired (the same inference problem
   that forbids directory-presence detection), so adopting whatever configs
   survive would permanently bless a pre-migration deletion. Update/audit
   mode therefore *proposes* a wired-provider set and the user confirms it;
   an adopted harness without the declaration stays a loud diagnostic
   unconditionally — not only when hook configs happen to be present — until
   confirmation happens. Structural validation, never byte-pinning.
   *Acceptance: negative fixtures fail check-harness for each of — the
   empirical reproduction above (hooks object deleted), a deleted provider
   config on a declared provider, a guard moved to the wrong event, a
   weakened matcher, and a command pointing at a missing script; a
   legacy-upgrade fixture (pre-declaration conf, adopt via update, delete
   hooks) also fails; a pre-migration-deletion fixture (delete a provider
   config, then migrate) proves the deleted provider cannot be silently
   omitted — the undeclared diagnostic persists until the set is confirmed;
   a tailored-but-complete config still passes.*
2. **Agent-stub coherence** — give `CANONICAL_AGENTS` a consumer (declared in
   `harness.conf` since v0.3.0, read by nothing), with **bidirectional set
   equality**, mirroring what check #3 already gives skill stubs. First
   establish the machine-readable routing source, because it does not exist
   yet: canonical agent docs under `docs/agents/` carry **no frontmatter** —
   the routing description lives only in the four hand-written provider
   stubs, so "stub matches canonical" has nothing deterministic to match
   against today. Add `name`/`description` frontmatter to every canonical
   agent doc (the same shape SKILL.md already uses). The provider set is
   **declared, not assumed or inferred** — the same contract as item 1's
   hook wiring, and for the same reasons: init supports subset installs, so
   hardcoding all four agent-capable dirs would fail legitimate subsets
   after upgrade, while inferring from existing directories lets deleting a
   whole agents dir bypass the check; and the existing `PROVIDERS` variable
   cannot serve (it models *skill-stub* destinations — excludes `.codex`,
   includes `.agents`). Add an `AGENT_PROVIDERS`-style declaration populated
   at init and explicitly confirmed (never inferred) during legacy
   migration. Then require, per declared provider: every canonical doc has a
   stub (in that provider's filename format), every stub points at an
   existing canonical doc, and each stub's routing description matches the
   canonical frontmatter — or fold agent stubs into `sync-agent-skills.sh`
   generation outright, which yields all of this for free. One-way
   validation is not enough: it passes after a provider's stub is deleted,
   and after a new canonical persona ships with no stubs at all.
   *Acceptance: canonical agent docs carry the frontmatter and the existing
   stubs are migrated to match it; a fixture that changes only the canonical
   description fails check-harness for every declared provider's stub until
   they are updated/regenerated; stale-description, missing-stub, and
   orphan-stub fixtures each fail; a legitimate subset declaration passes
   while deleting a declared provider's entire agents dir fails; grep shows
   `CANONICAL_AGENTS` consumed by mechanism code.*
3. **Ship the described-but-missing wiring** — the provider matrix documents
   an OpenCode TS plugin shim, but `templates/providers/opencode/` ships only
   `opencode.json`; the matrix's Cursor `guard-config.sh` row reads "not
   wired" while noting the generic pre-tool hook is pre-edit-capable. Either
   ship the shim template and the Cursor wiring, or stamp an explicit dated
   descope rationale into those matrix rows — both resolve the
   documented-vs-shipped ambiguity. Whichever way it lands, reconcile
   *every* shipped surface that repeats the claim — the matrix rows alone
   are not the whole story: `references/pattern.md` names the OpenCode shim
   as one of the four one-line wirings, and the hooks README and
   `references/modes/init.md` carry their own wiring statements — a
   matrix-only edit would leave shipped docs telling users the opposite of
   what ships. *Acceptance: every shipped wiring claim (at minimum
   `provider-matrix.md`, `pattern.md`, `init.md`, and the templates' hooks
   README) agrees with the shipped templates for the chosen outcome; any
   shipped shim carries a regression test like the bash hooks do.*
4. **Runtime-prerequisite preflight at init/update** — without `jq` every
   guard fails open; today that surfaces only as a doctor WARNING when
   init's final `check-harness.sh` run happens to be read. Add an explicit
   early preflight step to init and update modes that names any missing
   prerequisite and asks the user to acknowledge before scaffolding a harness
   whose feedback layer would be inert. *Acceptance: `init.md`/`update.md`
   carry the step; the doctor warning remains as the ongoing signal; the
   fail-open posture itself is untouched.*
5. **Old-template recovery for copied/plugin installs** — update mode's
   tailored-file diff needs the *old* kit version's templates, documented as
   recoverable from "the kit repo's git tag matching the manifest header
   version" — but plugin installs copy only `plugins/harness-kit/` into
   cache, copied installs need not retain `.git`, and the kit repo is
   private until launch-readiness item 7 lands. Define the recovery path per
   install channel (fetch from a declared repo, or persist the installed
   base locally at init) and test it — `test-install.sh`'s update fixtures
   construct source directories and never exercise tag recovery.
   *Acceptance: `update.md` states the recovery path for each install
   channel; a `test-install.sh` case covers the no-local-git path.*
6. **Per-provider acceptance floors for recorded eval cells** — both Codex
   tiers sit at 0/3 on both add-skill tasks (`add-skill-sync`,
   `hn-add-skill`) while capability failures stay informational by policy,
   and no Codex plugin-activated cells exist (`eval.sh` invokes `codex exec`
   bare; the v0.12.0 audit's 0/3-installed vs 3/3-plugin-activated flip was
   measured on Claude haiku only). Recording those cells first needs an
   **execution-variant dimension** in the results schema and baseline keys:
   cells are currently identified by `(task, provider/model)` alone, so a
   plugin-activated run of the same Codex model would silently *replace* the
   bare cell instead of coexisting with it — erasing the comparison the
   threshold decision depends on. Add the dimension (bare vs
   plugin-activated), then record the Codex plugin-activated cells for the
   add-skill tasks, then make and log the threshold decision: which
   capability cells, if any, gate a release — with the rationale either way.
   *Acceptance: a collision test proves a bare and a plugin-activated cell
   for the same task/provider/model coexist in
   [../../evals/baselines.json](../../evals/baselines.json); the new cells are
   recorded at the standard trial count; the decision lands in this plan's
   Decisions log and in [../../evals/README.md](../../evals/README.md) if the
   policy changes.*

## Out of scope

- Byte-pinning provider configs in `scripts/.harness-manifest` — they are
  tailored policy by design; the fix is semantic validation, not checksums.
- Full model-graded golden tasks for complete `init`/`audit`/`update`
  journeys — the deterministic floor (`test-install.sh`) plus item 5's
  recovery case keep covering the mechanics; whole-journey behavioral tasks
  are their own eval-bank theme if item 6's decision demands them.
- Any change to the guards' fail-open posture (a broken guard must never
  block work — Security Checklist).
- Root-README dead-link scanning — already owned by the queued
  [../outcome-telemetry-and-doc-gardening.md](../outcome-telemetry-and-doc-gardening.md).

## Dependencies

None hard. Item 6's plugin-activated Codex runs cost real model spend (same
explicit go-ahead discipline as v0.12.0's baseline recording). Item 3's
matrix edits follow the citation discipline in
[../../conventions/templates.md](../../conventions/templates.md).

## Verification

The finding-1 reproduction (fresh clone, `jq 'del(.hooks)'
.claude/settings.json`, run `check-harness.sh`) exits non-zero; a
stale agent-stub description exits non-zero; `bash scripts/verify.sh` green
end to end; every new or changed matrix row stamped; item 6's cells present
in `baselines.json` with the threshold decision logged.

## Progress

- 2026-07-13 — **Activated as v0.14.0.** An execution + delegation plan was
  built on top of this scope and reviewed by Codex `gpt-5.6-sol` (session
  `019f5d11`), which returned six findings (verdict initially "not sound as
  written"); all six were verified in-repo and folded in before build. The
  structural results: a single committed **activation-contract commit** every
  worktree branches from; **single-writer file ownership** (item 2's
  hand-authored→generated conversion touches the same doc surfaces as item 3,
  incl. the shipped `templates/docs/agents/code-reviewer.md:144`, so WS-B
  serializes after WS-A rather than running parallel); the `.harness-manifest`
  treated as a **lead-owned integration artifact**; item 6's real key located
  at `eval-harness.sh:96` (`group_by([.task,.provider,.model])`), not the eval
  wrapper; and a **mandatory integrated `verify.sh` barrier** before the Terra
  diff review, adding a real-shipped-templates tuple fixture and a
  second-update idempotency fixture. Delegation: **WS-A** (Opus 4.8, items 1+2)
  ∥ **WS-C** (Sonnet 5, item 6 code) in parallel worktrees; then a serial tail
  — **WS-B** (Sonnet 5, item 3 descope), items 4+5 (lead), item 6 paid runs
  (lead) — then integrated verify + Codex `gpt-5.6-terra` + release.
- 2026-07-13 — Adversarial review round five (Codex, same day) confirmed
  round four holds and extended the declared-set contract to item 2: the
  agent-provider set must be its own declaration (`AGENT_PROVIDERS`-style,
  init-populated, migration-confirmed) — hardcoding all four dirs breaks
  legitimate subset installs, inference lets a deleted agents dir bypass the
  check, and `PROVIDERS` cannot serve because it models skill-stub
  destinations (excludes `.codex`, includes `.agents`). Subset-passes and
  deleted-dir-fails fixtures joined the acceptance list.
- 2026-07-13 — Adversarial review round four (Codex, same day) confirmed
  round three holds and caught that item 2 was unimplementable as written:
  canonical agent docs carry no frontmatter (verified — the routing
  description exists only in the four hand-written stubs), so "stub matches
  canonical" had no deterministic source. Item 2 now establishes
  `name`/`description` frontmatter on canonical agent docs first, migrates
  the existing stubs to it, and adds a canonical-description-change fixture.
- 2026-07-13 — Adversarial review round three (Codex, same day) confirmed
  rounds one and two hold and closed the last hole in item 1's migration
  contract: adopting the wired-provider set by inference from surviving
  configs would permanently bless a config deleted *before* migration (the
  same filesystem-can't-know problem that forbids directory-presence
  detection). Migration is now explicit user confirmation of a proposed set,
  the undeclared diagnostic fires unconditionally until confirmed, and a
  pre-migration-deletion fixture joins the acceptance list.
- 2026-07-13 — Adversarial review round two (Codex, same day) confirmed the
  round-one fixes hold and tightened three acceptance criteria: item 1
  gained the legacy-install migration path (a pre-declaration `harness.conf`
  is tailored/diff-only during update, so without explicit adoption the new
  check would validate zero providers on every upgraded install) plus its
  upgrade fixture; item 2's validation became bidirectional set equality
  (one-way checking passes after a deleted stub or an all-stubs-missing new
  persona) with missing-stub/orphan-stub fixtures; item 3's acceptance grew
  from "matrix rows agree" to reconciling every shipped wiring surface
  (pattern.md, init.md, the hooks README) under either outcome.
- 2026-07-13 — Adversarial review of this plan's first draft (Codex, same
  day) strengthened it in three places, all verified before adoption:
  item 1 now requires per-guard (config, event, matcher, script) tuples plus
  a *declared* wired-provider set — presence-only checking would stay green
  after a guard swap, a weakened matcher, or a deleted config on a
  stub-holding provider dir; item 6 now adds an execution-variant dimension
  first — baseline cells are keyed `(task, provider/model)`, so a
  plugin-activated re-run would silently overwrite the bare cell it must be
  compared against; and README's "update mode recovers old templates by tag"
  Status line was qualified to stop asserting the recovery path item 5 exists
  to define and test.
- 2026-07-13 — Scoped from the post-v0.13.0 cross-review (Codex
  gpt-5.6-sol). Each adopted finding was independently re-verified in-repo
  first; the hook-wiring hole was reproduced empirically (full
  `check-harness.sh` green on a clone with `.claude/settings.json`'s `hooks`
  object deleted). Review claims *tempered* during verification: the
  "CI reports coherent after hooks disabled" finding understated
  `guard-config.sh`'s runtime denial of tool-mediated config edits — the
  missing layer is CI/shell-edit enforcement, which item 1 adds; the "no
  preflight" finding understated that init's final `check-harness.sh` run
  already prints the doctor WARNING — the gap is acknowledgment, not
  detection. The review's README dead-link find was fixed inline the same
  day (two Status-section links pointed at the plan's pre-activation path).

## Decisions

- 2026-07-13 — **Item 3: descope** (maintainer). The OpenCode `.opencode/plugins/*.ts`
  shim and the Cursor `guard-config` wiring are descoped for v0.14.0 with a
  dated matrix rationale; item 3 becomes doc-only. Keeps the hook-tuple
  contract (claude/cursor/codex) stable and retires the sol review's finding 4
  (an untested TS shim on an under-resourced tier). The scope plan already
  accepts a dated descope as resolving the documented-vs-shipped ambiguity.
- 2026-07-13 — **Item 6: paid runs approved this cycle** (maintainer). The
  Codex plugin-activated add-skill recordings and the per-provider
  acceptance-floor decision ship in v0.14.0, run after the execution-variant
  dimension lands so they don't key-collide.
- 2026-07-13 — **Items 1+2 stay in one Opus worktree** (WS-A), internally
  sequenced: they share `check-harness.sh`, `harness.conf`, `install-lib.sh`,
  and the agent-generation doc surfaces, so splitting them would only
  manufacture self-conflict.
- 2026-07-13 — One plan, not three: the six findings share a theme —
  assurance that documented wiring is real — and splitting the recovery and
  eval-policy items out would recreate the unowned-gap problem the review
  flagged (its finding 5 was precisely that no queued plan owned the parity
  gaps).

## Next action

Activation is committed. Launch **WS-A** (Opus, items 1+2) and **WS-C**
(Sonnet, item 6 code) in parallel isolated worktrees off the activation commit.
WS-A's first step: design item 1's per-provider required-event table from the
now-frozen provider-matrix hook rows (`references/provider-matrix.md:95–99`;
wired = claude/cursor/codex, cursor's `guard-config` legitimately absent) — it
anchors the headline reproduction and the rest of the checks follow its shape.
