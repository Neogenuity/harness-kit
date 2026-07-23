# Adopter test descope (superseded)

**Status:** superseded 2026-07-22 — absorbed into
[standard-consumer-layout.md](standard-consumer-layout.md) as its Phase 2;
the retired-file prerequisite below ships first as that plan's Phase 1
(v0.21.0). Kept for the original problem statement and the fixture contract,
which the absorbing plan implements unchanged. Originally: queued — blocked
on a retired-file mechanism. Raised during the v0.20.0 install-suite split;
seconded as a blocker-severity finding by the codex review of that split (an
adopter upgrading across a version that drops a shipped file ends red: the
orphaned file stays on disk, `harness_update_apply` keeps it,
`harness_repin_manifest` drops its pin, and check #9c flags it as
present-but-unpinned).

## Problem

Every adopter repo receives and runs the full install/update conformance
suites (`test-install-core.sh`, `test-install-update.sh`,
`test-install-recovery.sh` — see `_HARNESS_MECHANISM_TOPLEVEL` in
`install-lib.sh`). Those suites exist to prove harness-kit's own
install/update/recovery contract; an adopter's `check-harness.sh` check #6
re-proves it on every audit, paying for harness-kit's historical upgrade
matrix instead of their own project and installed policy.

The v0.20.0 split reduced the cost sharply (recursive fixture checker runs
went from 9 sites to 1; the suites run ~46s serial, ~28s max parallel, down
from ~231s), so this is no longer urgent — it is an ownership-boundary
cleanup, not a performance fix.

## Target

Keep the exhaustive install/update suites as **maintainer-only** conformance
tests (like `scripts/harness/tests/test-provider-templates.sh` and
`scripts/harness/tests/test-template-sync.sh`, root-only and `# tailored`-pinned). Adopters
keep only:

- static harness integrity checks (`check-harness.sh` itself),
- hook behavioral tests relevant to their installed configuration
  (`scripts/harness/hooks/test-*.sh`),
- a small post-init/post-update smoke test (install a throwaway fixture,
  assert the checker is green — roughly today's clean-init case).

## Prerequisite: retired-file mechanism

Update mode never removes a file, so descoping (or any future rename) orphans
the old copies in adopter repos and check #9c turns their audit red. Before
descoping, `install-lib.sh` needs a retirement contract, e.g.:

- a `_HARNESS_RETIRED_TOPLEVEL` list the incoming kit ships;
- `harness_update_apply` emits `remove <path>` for a retired file only when it
  is **pristine** (on-disk sha matches its pin) and not `# tailored`; drifted
  or tailored copies are kept and reported for manual review;
- `harness_repin_manifest` already drops pins for absent files — no change;
- fixture coverage in `test-install-update.sh`: pristine-retired removed,
  drifted-retired kept + flagged, tailored-retired kept with pin carried.

The v0.20.0 release notes document the interim caveat for the one existing
install (this repo, pre-launch): delete the orphaned `scripts/harness/tests/test-install.sh`
by hand after updating, then re-pin.
