# Install / update verification

Status: queued

## Objective

Prove the deterministic mechanics of the kit's core product — the `init` /
`audit` / `update` workflow — with an automated fixture suite: install into a
clean fixture repo, confirm a partial harness's hand-written files survive
untouched, run a no-op update, roll a mechanism upgrade forward, and confirm a
`# tailored` file survives an update untouched — each asserted against expected
filesystem state, no model in the loop. The model-graded quality of authoring
and merges is delegated to the behavioral-evals plan, not claimed here.

## Value

The kit's principal boundary is the install/upgrade workflow (kit
[SKILL.md](../../plugins/harness-kit/skills/harness-kit/SKILL.md) `init` /
`update`), yet it is the *only* mechanism with no automated test. The suites
today cover individual scripts and hooks thoroughly, but nothing proves the
workflow that assembles them: a clean install, a partial-harness merge, a
version upgrade that preserves tailored files. Automated fresh-repo testing
was explicitly deferred twice — at the repackage release and in the
plans-machinery plan (a manual fixture recipe was substituted) — so the gap
is real and currently unowned. A coverage audit (2026-07-11) named it the
largest unplanned reliability gap.

The audit's key observation makes it tractable: **the mechanical subset of
the expected filesystem state can be checked deterministically** — mechanism
files copied and `chmod +x`'d, `.harness-manifest` generated with correct
checksums, the native secret-deny lists mirroring `SECRET_PATTERNS`,
`.harness/` appended to `.gitignore`, and on update the
checksum-match-→-replace vs `# tailored`-→-diff-only branch. None of that
needs a model. The **judgment** parts — merging a hand-written
`.claude/settings.json` without clobbering it, authoring `AGENTS.md` *from the
codebase*, producing the `audit` gap table — are agent-driven, not filesystem
ops; this plan does **not** claim to test those deterministically. It owns the
mechanism; their *quality* is a behavioral-evals golden task (the boundary is
drawn explicitly in Scope). Where a judgment step has a deterministic *floor*
(init must never overwrite a pre-existing hand-written file; `check-harness.sh`
must flag seeded drift), that floor is asserted here; the model-graded quality
above it is not.

## Scope

1. **Extract the deterministic mechanics** into a testable unit. `init` and
   `update` are prose steps in SKILL.md today; the *filesystem-mechanical*
   subset — copy `templates/scripts/` → `scripts/`, `chmod`, append
   `.harness/` to `.gitignore`, generate `.harness-manifest`, and update's
   replace-vs-diff decision per manifest line — becomes a small script/library
   (e.g. `templates/scripts/install-lib.sh`) the prose flow calls and tests
   can drive. Authoring steps (AGENTS.md, conventions) stay prose. *Acceptance:
   the extracted unit is pure filesystem ops, no model calls, sourced by both
   the prose flow and the tests.*
   **Manifest coverage** (the new mechanism files must not escape integrity
   checking): the init manifest producer (SKILL.md step 8) enumerates a fixed
   file list — `scripts/hooks`, `sync-agent-skills.sh`, `check-harness.sh`,
   `test-check-harness.sh`, `verify.sh`. Extend that enumeration (and the
   `verify.sh` manifests gate + this repo's own manifest) to include the new
   `install-lib.sh` and `test-install.sh`, so a fresh install checksum-pins
   them and update manages them like any other mechanism file. Re-pinning
   alone is not enough — an un-enumerated file is invisible to the manifest.
   *Acceptance: a fixture's generated manifest lists both new files; mutating
   either without re-pinning fails `check-harness.sh`.*
2. **Fixture harness** built on the plans-machinery fixture recipe: a helper
   that spins up a throwaway git repo (minimal source file + manifest) in a
   scratch dir, runs an operation, and tears down. Reused by later plans
   (evals per-trial isolation, governance install checks). *Acceptance:
   `test-install.sh` creates and destroys its fixtures with no residue outside
   the scratch dir.*
3. **The five deterministic cases** (`scripts/test-install.sh`, wired into
   `verify.sh`) — each drives the *library* (scope item 1), not an agent, so
   each is genuinely reproducible:
   (a) **clean init** — mechanism installed, executable bits set, manifest
   generated and self-verifying (including the item-1 new files), native deny
   lists mirror `SECRET_PATTERNS`, `check-harness.sh` passes in the fixture;
   (b) **non-clobber floor** — the library, run over a fixture that already
   has a hand-written `.claude/settings.json` and `AGENTS.md`, leaves those
   pre-existing files byte-for-byte untouched (the deterministic floor of the
   SKILL.md "never overwrite hand-written content" rule; the *quality* of any
   subsequent agent-authored merge is a behavioral-evals task, not asserted
   here);
   (c) **no-op update** — running update at the same manifest version changes
   nothing (idempotence; clean `git status` in the fixture);
   (d) **mechanism upgrade** — a fixture pinned to an older manifest checksum
   for an *untailored* mechanism file gets it replaced with the new version
   and the manifest re-pinned;
   (e) **tailored-file preservation** — a fixture with a `# tailored` line
   whose content differs from the template is *not* replaced by update; it is
   diffed only, and its checksum pin is honored.
   *Acceptance: all five pass standalone and under `verify.sh`; each asserts
   concrete post-state, not just exit code.*
4. **Deterministic drift detection**: a case that runs `check-harness.sh`
   (the scripted, model-free core of `audit`) against a drifted fixture — a
   missing native deny entry, a stub out of sync — and asserts it exits
   non-zero naming the real problem. The agent-authored `audit` *narrative*
   (the graded gap table with prioritized fixes) is judgment, so it is a
   behavioral-evals golden task, not asserted here. *Acceptance:
   `check-harness.sh` flags each seeded drift in the fixture.*
5. **Manifest enumeration + re-pin + CI**: this is a mechanism change (new
   template lib + new test). Beyond re-pinning `.harness-manifest`, extend the
   manifest-producer file list per scope item 1 so `install-lib.sh` and
   `test-install.sh` are enumerated, and ensure `test-install.sh` runs in the
   `harness-check`/`verify.sh` gate.

## Out of scope

Model-driven end-to-end "does the authored AGENTS.md read well" (behavioral-
evals golden task); performance of install; multi-provider matrix expansion
(plans-machinery); a full rewrite of `init`/`update` into a single script —
only the deterministic subset is extracted, authoring stays prose.

## Dependencies

The plans-machinery release — its documented fixture recipe (scratch git repo
with a minimal manifest and one source file) is scope item 2's substrate; this
plan turns that manual recipe into an automated suite.

## Verification

`bash scripts/verify.sh` green including `test-install.sh`; the five
deterministic cases and the drift-detection case pass standalone; the
generated fixture manifest enumerates `install-lib.sh` and `test-install.sh`
(mutating either without re-pinning fails `check-harness.sh`); a deliberately
mis-pinned manifest line makes the mechanism-upgrade case fail loudly (proving
it asserts real state); no fixture residue outside the scratch dir; this repo's
manifest re-pinned.

## Progress

- 2026-07-11 — Scoped from the 2026-07-11 standards-coverage audit, which
  found the install/upgrade workflow (the kit's core product boundary)
  untested and named it the largest unplanned reliability gap. Framed around
  the audit's insight that the mechanical subset is deterministically
  checkable without a model; the model-driven half is delegated to the
  behavioral-evals plan.

## Decisions

- 2026-07-11 — Deterministic mechanism here, model judgment in evals: split
  the untested workflow at the model boundary. Extracting only the filesystem-
  mechanical subset (not a full `init` rewrite) keeps authoring flexible while
  making the load-bearing mechanics testable — the active v0.5.0 plan deferred
  the full extraction, this takes up only the part a test can pin.

## Next action

After plans-machinery ships: extract the deterministic install/update
mechanics into `install-lib.sh` and stand up the throwaway-fixture helper,
then write the clean-init case first.
