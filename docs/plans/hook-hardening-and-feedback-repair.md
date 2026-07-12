# Hook hardening + feedback repair

Status: queued

## Objective

Close the live-layer self-protection gaps the 2026-07-12 project review
confirmed by probe, repair the feedback channels current provider docs show
degraded or at risk, and refresh the provider-matrix facts that review's
verification pass surfaced — so the hook layer's *feedback* story is as honest and tested
as the CI layer's *integrity* story.

## Value

The 2026-07-12 review re-verified the matrix against live provider docs and
probed the installed guards with real payloads. Three findings are
self-protection gaps with a confirmed reproduction: `scripts/harness.conf`
(the secret guard's single pattern source) is editable live, so the guard can
be disarmed in-session two steps before the CI manifest notices;
`.claude/settings.local.json` is writable, absent from the manifest, and
kept out of git in the standard Claude Code setup (here by the user-global
gitignore — this repo's `.gitignore` never lists it), so a
`disableAllHooks: true` write is caught by **no layer at all** — the only
such hole in the layering story the risky-actions doc tells; and three of
the four MCP config files check #8c audits (`.mcp.json`, `.cursor/mcp.json`,
`.codex/config.toml` — `opencode.json` is already guarded) are writable
live, caught only in CI. Two
more are feedback-channel failures: Cursor now documents that non-JSON hook
stdout is ignored (the lint-feedback arm is *dead* there, not "needs
re-testing"), and Claude Code's Stop payload field `stop_hook_active` has
left the current docs while remaining empirically live (captured from CLI
2.1.207) — `hook_advise_once` depends on it and would degrade *silently* to
never-surfaced advisories if the field is dropped. Hooks stay guardrails, not
boundaries
([pattern.md](../../plugins/harness-kit/skills/harness-kit/references/pattern.md))
— but a guardrail whose cheapest bypass is a one-line conf edit, or whose
feedback never renders, isn't earning its keep.

## Scope

1. **Close the guard-coverage gaps** — extend the default `PROTECTED_PATHS`
   in
   [guard-config.sh](../../plugins/harness-kit/skills/harness-kit/templates/scripts/hooks/guard-config.sh)
   (template first, then roll into the installed copy) with
   `scripts/harness.conf`, `.claude/settings.local.json`, `.mcp.json`,
   `.cursor/mcp.json`, and `.codex/config.toml`. Mirror every new path into
   `test-guard-config.sh` deny cases in both payload layouts (direct
   `file_path` and apply_patch envelope) plus an allow-case control. Update
   the hook header, the kit SKILL.md init step 4, and the two convention docs
   (template + installed) where they enumerate guard coverage — including the
   honest note that Cursor has no pre-edit event, so these denials fire on
   Claude Code/Codex only. Post-init `harness.conf` tailoring now rides the
   existing `HARNESS_ALLOW_MECHANISM_EDITS=1` ceremony — document that.
   *Acceptance: the review's probe payloads for all five paths exit 2 in both
   layouts; the escape hatch still passes; every new path has a regression
   case; `verify.sh` green.*
2. **Repair the Cursor feedback arm** — verify the current response schema
   for `afterFileEdit` against Cursor's hooks doc (plain-text stdout is
   documented ignored), then convert `hook_feedback`'s Cursor arm in
   [lib.sh](../../plugins/harness-kit/skills/harness-kit/templates/scripts/hooks/lib.sh)
   to the verified JSON shape — no recognized layout may emit plain text. If
   no documented field surfaces feedback text on that event, the honest
   outcome is a stamped matrix note that lint feedback degrades to the log on
   Cursor — never dead plain-text. *Acceptance: `test-format-feedback.sh`
   asserts Cursor-layout stdout parses as JSON (or the documented degradation
   is stamped in the matrix); the Cursor feedback cell restamped.*
3. **Future-proof advise-once** — (a) restamp the `stop_hook_active` fact as
   "undocumented in current docs, empirically present in CLI 2.1.207
   (captured payload, 2026-07-12)"; (b) add a payload-independent loop guard
   — a marker under `.harness/` keyed on the payload's session/conversation
   id plus a warnings digest — used when a Stop payload carries neither
   `stop_hook_active` nor `loop_count`, so the protocol survives the field's
   removal without silently muting advisories (decide at implementation
   whether it becomes primary; define marker cleanup); (c) evaluate the
   now-documented Stop `hookSpecificOutput.additionalContext` channel as the
   advisory vehicle and record the adopt/reject decision here. *Acceptance:
   `test-advise-once.sh` gains a no-loop-flag payload case proving
   advise-exactly-once; matrix stamped; decision logged in this plan.*
4. **Model-visible deny reasons** — on `tool_input` layouts where
   `hook_event_name` is `PreToolUse` (Claude Code and Codex both accept
   `permissionDecision`), `hook_deny` emits the exit-0 JSON deny carrying the
   reason; the portable exit-2 stays for the Cursor/unknown layouts,
   non-PreToolUse events, **and as the fallback whenever JSON construction
   fails** — a malformed exit-0 deny would fail open (allow), the one
   direction this protocol must never fail. *Acceptance: guard tests assert
   the JSON deny shape on tool_input layouts, exit-2 on the Cursor layout,
   and exit-2 with jq absent; the matrix deny-semantics bullet updated and
   restamped.*
5. **Matrix refresh from the verification pass** — add stamped facts for
   Cursor's grown surface (`beforeShellExecution`, `beforeMCPExecution`,
   generic `preToolUse`/`postToolUse`, per-hook `failClosed`); evaluate
   wiring the guard-secrets shell-token scan to `beforeShellExecution` in the
   shipped `.cursor/hooks.json` template — wire only what the payload and
   deny semantics verifiably support; re-verify `eval.sh`'s pinned CLI
   invocations (header stamps Claude Code 2.1.172; current CLI is 2.1.207)
   and restamp. *Acceptance: every touched fact carries a fresh stamp
   cross-referenced in the matrix Sources; any new wiring ships with a guard
   test case; the `eval.sh` header restamped.*

## Out of scope

Making hooks an enforcement boundary (the pattern's guardrail language
stands — this plan removes cheap bypasses and repairs feedback, nothing
more); the OpenCode plugin shim (posture unchanged: native permissions + CI
backstop); reviewer persona and eval-bank growth (their own plans);
org-managed settings surfaces (provider-managed, documented expectations
only).

## Dependencies

None — deliberately schedulable immediately. Mechanism changes ride the usual
discipline: template first, regression test beside it, roll-forward into
`scripts/`, manifest re-pin, and a CHANGELOG migration note stating what
update mode replaces (`guard-config.sh`, `lib.sh`) vs. never touches
(`harness.conf`, `verify.sh`); the version is assigned at activation
(mechanism changes make it at least a minor bump per the release skill).

## Verification

`verify.sh` green on templates and installed copies. The review's probes
re-run and now deny — e.g.
`printf '{"tool_input":{"file_path":"scripts/harness.conf"}}' | bash scripts/hooks/guard-config.sh`
exits 2, likewise for `.claude/settings.local.json` and `.mcp.json`, in both
payload layouts. No recognized-layout hook path emits plain text on Cursor.
Matrix stamps current with sources. CHANGELOG migration notes state what
update mode replaces (`guard-config.sh`, `lib.sh`) vs. never touches
(`harness.conf`, `verify.sh`).

## Progress

- 2026-07-12 — Scoped from the 2026-07-12 project review: provider matrix
  re-verified against live Claude Code / Cursor / Codex / Agent Skills /
  OpenCode docs; guard-config probed with real payloads (`harness.conf`,
  `.claude/settings.local.json`, `.mcp.json` all passed — confirmed gaps); a
  live Stop payload captured from Claude Code CLI 2.1.207 confirmed
  `stop_hook_active` is still sent though no longer documented; Cursor docs
  now state non-JSON hook stdout is ignored.

## Decisions

- 2026-07-12 — **Queued #1, ahead of eval-discrimination**: probe-confirmed
  containment gaps (one covered by no other layer) outrank measurement
  growth — the same combined-controls logic that pulled the v0.10.0 baseline
  forward
  ([completed/v0.10.0-execution-governance-baseline.md](completed/v0.10.0-execution-governance-baseline.md)).
  Nothing downstream consumes this plan, so the reviewer-loop chain through
  eval-discrimination is unaffected.
- 2026-07-12 — **Exit-2 stays the deny fallback**: the JSON deny channel is
  adopted only where its construction can be proven in-hook; a deny must
  never fail open.
- 2026-07-12 — **Hooks stay guardrails**: no language change in pattern.md;
  the convention docs keep labeling these controls in-turn advisory
  feedback, and this plan's coverage additions don't re-promise a boundary.

## Next action

Scope item 1: extend `PROTECTED_PATHS` in the guard-config template plus its
test cases, then roll forward and re-pin — the highest-severity finding, and
independent of the doc-verification items.
