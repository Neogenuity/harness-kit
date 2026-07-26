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
- **19 remaining here-doc-fed check loops can still fail open** — v0.34.0 fixed
  the three in `check-drift.sh` that [#15](https://github.com/Neogenuity/harness-kit/issues/15)
  named, but the same shape (`done <<EOF` / `<<< "$var"`, whose temp file bash
  3.2 writes to `$TMPDIR` and then the CWD) remains in `check-instructions.sh`
  (7), `check-doctor.sh` (7), `install-lib.sh` (2), `hooks/format.sh` (1),
  `check-docs.sh` (1), and `eval-harness.sh` (1). Severity splits: the
  ERROR-raising loops in `check-instructions.sh` are true false-pass risks like
  #9c was; the `check-doctor.sh` predicates lose warnings or fail *closed*
  (safe-noisy); `install-lib.sh:187` sets `bad=1` outside its loop, so only the
  per-path detail is lost. Deferred as a class because the obvious uniform
  conversion is unsafe: about half of these `return`/`break` mid-loop, and
  process substitution would leave the `printf` writer taking an EPIPE under an
  inherited-ignored SIGPIPE — the phantom-failure mode this repo hit live twice
  (v0.16.0 macOS, v0.20.0 ubuntu; see the comment above check #9c). Each needs
  the run-to-completion property checked individually. Promote when a
  false-pass is observed in the wild, or bundle with the next
  `check-instructions.sh` change (trigger: any report of a checker passing on a
  repo that should have failed).
- **haiku reward-hacks the neuter-check** — the negative-no-neuter-check
  scenario passes ~2/3 on haiku-tier models (recorded 2026-07-12). Revisit
  when re-baselining the eval matrix on newer cheap-tier models.
