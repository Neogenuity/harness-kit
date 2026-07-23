# ADR 011 — Single provider declaration + kit-owned capability table

**Status:** accepted (v0.25.0)

## Context

Through v0.24.0 an adopter declared provider wiring four times in
`harness.conf`: `PROVIDERS` (which dirs get skill stubs), `HOOK_WIRED_PROVIDERS`
(which get hook configs, validated tuple-by-tuple), `AGENT_PROVIDERS` (which get
generated agent stubs), and `EXECUTION_PROFILE_PROVIDERS` (which adopt the
sandbox floor). Correct *membership* of the first three is not repo policy — it
is **kit knowledge**: `.codex` reads `.agents/skills/` natively so it needs no
skill stub; `.opencode` has no bash hook shim so it cannot be hook-wired; each
provider's agent stub takes a specific dialect (Codex TOML, OpenCode Markdown +
`mode: subagent`). That knowledge was re-encoded in three places —
`sync-lib.sh`, `check-instructions.sh`, and the `harness.conf` comments — and an
adopter had to reproduce it correctly across four lists. This was the last of
the "ownership encoded five ways" cleanups still open before the pre-launch
layout freeze; done now it is a one-repo re-pin, done after launch it is a
breaking `harness.conf` migration for every adopter.

## Decision

**One declaration, kit-owned facts.** An adopter declares a single
`HARNESS_PROVIDERS` — the provider dirs this repo wires. A kit-owned capability
table, `scripts/harness/lib/provider-caps` (plain text, bash-3.2
read/awk-parseable, no jq — ADR 002; sha-pinned + guard-protected mechanism like
`kit-manifest`), holds one row per provider with the facts that decide each
list's membership: `skill_stubs`, `agent_dialect`, `hook_config`, `exec_config`.

The three **wiring** facets derive from `HARNESS_PROVIDERS` filtered through the
table (`provider-lib.sh`, sourced by `check-common.sh` and `sync-lib.sh`), with
override-or-derive resolution: an explicit `harness.conf` value wins (the escape
hatch), else the set is derived, else it stays unset so the existing
declared-not-inferred diagnostics still fire. A new check (`#8f`) validates the
declaration itself — every entry must be a known provider, each once.

**Execution profiles stay an explicit opt-in — the deliberate asymmetry.**
`EXECUTION_PROFILE_PROVIDERS` is *not* derived. Skill/agent/hook wiring is
non-invasive registration; an execution profile imposes a strict runtime sandbox
floor (default-deny network, empty writable roots) that routinely conflicts with
local development. Auto-adopting a floor as a side effect of naming a provider
would be a footgun and would reverse ADR 008's deliberate opt-in. So the knob
stays explicit and unset-by-default; what changes is that its per-provider config
path and validator now live in the table too, and the declared set is validated
to be a subset of the wired providers (you cannot floor a provider you do not
wire). Rejected alternative: derive it like the others — rejected because a
declaration of *which providers I use* must never silently tighten my runtime.

**`sync` grows two generated artifacts.** `sync` (write) emits, per wired
provider, a committed `.harness/adapters/<slug>.md` wiring summary rendered from
the table + the resolved sets; `sync --check` keeps them current. Adapters are an
opt-in generated artifact (documentation, not functional wiring): `--check`
enforces completeness only once any exist, so a repo that never ran `sync` — and
every bare fixture — is not nagged. A separate `sync secrets [--check]`
subcommand (jq hard-required, unlike the rest of sync) generates the native
secret-deny mirrors from `SECRET_PATTERNS`: `.claude/settings.json` gets a
**deny-only** list (`Read(./P)` + `Read(**/P)`; the platform resolves
deny-beats-allow, so an allow list would be pointless and the guard hook is the
precise layer), `opencode.json` gets `**/P: "deny"` under `permission.read` and
keeps its hand-owned allow exceptions. Reconciliation is ensure-present +
preserve (over-denying a secret is safe, under-denying is the risk, so nothing is
removed); checks `#8`/`#8b` remain the independent verification and point at
`sync secrets` as the fix.

## Consequences

- An adopter maintains **one** wiring list plus the orthogonal execution opt-in;
  the four legacy lists survive only as explicit overrides for the rare
  provider-specific case.
- The wiring facts live in exactly one place (`provider-caps`); adding a provider
  is a one-row change there plus its frozen hook-tuple table and `#8e` validator
  in `check-instructions.sh` (the event/matcher contract and security-floor keys
  are richer than a table cell).
- New obligations: `provider-caps` + `provider-lib.sh` are sha-pinned mechanism;
  `#8f` gates the declaration; a shipped `test-sync-secrets.sh` covers mirror
  generation; the execution-profile asymmetry and the Claude deny-only /
  OpenCode allow+deny asymmetry are documented here and in `harness.conf`.
- Reopen trigger: a new provider whose wiring model does not fit the four
  capability columns (e.g. a provider needing a second workflow surface), or a
  decision to make execution-profile adoption derive after all.
