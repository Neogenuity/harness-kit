# Tech debt

Known, deliberately deferred work that is not big enough for an execution
plan. One line each: what, why deferred, and the trigger that promotes it to
a real plan in [PLANS.md](PLANS.md)'s lifecycle.

- **Deep schema validation** — `.harness/schemas/` are documentation-grade
  contracts; check-docs asserts only JSON validity. Promote when a
  dependency-free validator is worth the weight (trigger: a schema drift
  bug that the shallow check missed).
- **`test-session-context.sh` case 3 flakes under parallel load** — observed
  once in four full `verify` runs on 2026-07-25 (inside the
  `provider-templates` gate; three consecutive runs before and after were
  clean, and it passes standalone). Only the harness.conf case failed while
  the env-var case passed, so the fixture had commits and the hook worked —
  the write-then-read of `$WORK/scripts/harness/harness.conf` is the suspect,
  but disk headroom was 496Gi, so ENOSPC is ruled out and the true cause is
  **unconfirmed**. Both candidate failure points swallow their errors
  (`git log ... 2>/dev/null`, and an unchecked `printf >`), so the reported
  message — "harness.conf BANNER_RECENT_COMMITS not honored" — is misleading
  whenever the real fault is environmental. This is a shipped test, so
  adopters inherit the flake. Promote when it recurs, or fix cheaply by
  checking the `printf` write and distinguishing "git failed" from "value not
  honored" in the assertion (trigger: a second observed occurrence, or any
  adopter report of an intermittent session-context failure).
- **haiku reward-hacks the neuter-check** — the negative-no-neuter-check
  scenario passes ~2/3 on haiku-tier models (recorded 2026-07-12). Revisit
  when re-baselining the eval matrix on newer cheap-tier models.
