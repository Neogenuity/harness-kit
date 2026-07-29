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
- **~~19 remaining here-doc-fed check loops can still fail open~~ — RESOLVED**
  (see the topmost `CHANGELOG.md` entry). The trigger fired on 2026-07-26: both
  adopter repos reproduced it live, one losing the #8d hook-wiring validator to
  11 "cannot create temp file for here document" errors and an exit 0. All 16
  loops that run to completion now read through process substitution and assert
  they consumed their input (`assert_loop_ran`, `check-common.sh`). What is left
  is the residue below, deliberately.
- **Five here-doc-fed loops that exit early are still temp-file-backed** — the
  `mcp_inventory_lookup` name→pin lookup (`check-instructions.sh`), `_10e_covers`
  (`check-doctor.sh`), `apply_rules` (`hooks/format.sh`), and both `SRC_MAP`
  lookups in `scripts/test-template-sync.sh` `return` on the first match, so
  process substitution would leave the `printf` writer taking an EPIPE under an
  inherited-ignored SIGPIPE — the phantom-failure mode this repo hit live twice
  (v0.16.0 macOS, v0.20.0 ubuntu). Each fails **closed** if its redirection
  fails: the two lookups report "not found" (which their callers raise as an
  ERROR), and `apply_rules` runs no formatter, which is what an unconfigured
  repo does anyway. Noisy-but-safe is the correct direction, so they stay
  here-docs with a comment at each site saying so. Same for the script-feeding
  `python3 - <<'PY'` here-docs in #8e: a failed redirection makes python exit
  nonzero and the check reports "malformed TOML" — a false ERROR, never a false
  pass. Promote if a *false ERROR* from this class is ever reported by an
  adopter (trigger: a checker failing on a repo that should have passed, traced
  to a redirection rather than to the file it names).

  The residue is now enforced, not just recorded: the shipped
  `scripts/harness/tests/test-check-loops.sh` fails on any here-doc-fed `done`
  or `read` in the harness tree that lacks the marker comment. The first cut of
  that scan looked only at `done <<` in `lib/` and `hooks/`, which is exactly
  why it missed `verify`'s `read -r kind label cmdstr <<LINE` gate-config parser
  — since replaced with parameter expansion. When narrowing this scan, assume
  the narrowing is what hides the next one.
- **haiku reward-hacks the neuter-check** — the negative-no-neuter-check
  scenario passes ~2/3 on haiku-tier models (recorded 2026-07-12). Revisit
  when re-baselining the eval matrix on newer cheap-tier models.
- **Adopters get no CRLF protection for their installed harness** — issue #27
  fixed line endings for *this* repo's clone (root `.gitattributes`, plus the
  CRLF probe in `harness_validate_ship_contract`). The shipped product still
  has the identical defect one layer out: the kit installs `scripts/harness/**`
  into adopter repos and integrity-pins every file by sha256, but ships them no
  `.gitattributes`. A Windows adopter with `core.autocrlf=true` who commits the
  installed harness gets CRLF back on their next clone, and every pin breaks at
  once. The failure signature there is *worse* than the one #27 fixed — the
  probe reads only the source manifest, which is always LF after #27, so the
  adopter sees ~117 sha256 drift failures from `verify` with nothing anywhere
  naming line endings. Confirmed while fixing #25: with a CRLF *and* binary-mode
  manifest the reported path now reads `lists 'scripts/mech.sh' but it does not
  exist` — the `*` is stripped but the trailing CR is invisible, so the message
  shows a correct-looking path being reported missing. Any fix here should probe
  the manifest for CR the way `harness_validate_ship_contract` probes
  kit-manifest, not just harden another reader. Precedent says this is in scope
  for the kit:
  `harness_append_gitignore` and the opt-in `--formatter-ignore`
  `.prettierignore` block already exist to protect the same byte-exact surface
  from repo-wide tooling. Deferred because #27 as filed is about this repo's
  clone and the fix is worth shipping without widening it. Promote on the first
  Windows adopter report, or when adopter-side `.gitattributes` is picked up as
  part of a broader install-time repo-config pass (trigger: either of those).
