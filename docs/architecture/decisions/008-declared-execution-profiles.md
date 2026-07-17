# ADR 008 — Declared execution profiles with semantic floors

**Status:** accepted (v0.16.0)

## Context

Provider sandbox, network, and approval files are repository policy: they are
merged with hand-written configuration and must not be byte-pinned or replaced
on update. Presence is not enough to prove adoption. A provider directory may
exist only for generated skills, and after adoption a deleted profile is
indistinguishable from a profile the repository deliberately declined.

The providers also do not expose equivalent boundaries. Claude Code, Codex,
and Cursor have native sandbox controls with different escape and management
semantics; OpenCode exposes permission prompts but no OS or shell-network
boundary. One uniform file shape would either overclaim enforcement or reject
valid provider-specific policy.

## Decision

Execution-profile adoption is explicit in the tailored
`EXECUTION_PROFILE_PROVIDERS` set in `scripts/harness.conf`.

- Unset or empty means the optional profiles are not adopted. Legacy installs
  remain valid and update/audit may offer adoption without performing it.
- Init or update records only the provider subset the user confirms. The set is
  never inferred from surviving provider files.
- Once declared, `check-harness.sh` validates a provider-specific semantic
  floor: required sandbox/approval state where the provider has one, and the
  strongest honest permission posture where it does not. Missing, malformed,
  or policy outside an explicitly accepted tuple is an error.
- Claude's stable profile closes sandboxed egress but retains its standard
  permission-gated unsandboxed retry. This keeps host-integrated operations
  such as a push or nested provider eval possible after explicit user approval;
  `excludedCommands` remains empty so no command bypasses the sandbox
  automatically.
- Codex has two exact accepted network tuples: the stable network-off floor and,
  only after separate user confirmation, an experimental compatibility
  disjunction with network access on, broad local/private binding, exact
  localhost/127.0.0.1 domain rules, empty Unix-socket rules, and disabled
  dangerous proxy bypasses. The latter is an admitted weakening with documented
  public-domain and ownership-safe teardown limits, not a silent strengthening
  of the stable floor.
- Provider configuration stays tailored and non-clobbering. Updates propose a
  diff; they never overwrite a hand-written config or silently broaden the
  declaration.
- Experimental and administrator-enforced controls may define separately named,
  explicitly confirmed tuples. The stable profile never depends on them, and
  neither the validator nor the documentation describes them as portable
  guarantees.

## Consequences

- Deleting or weakening an adopted profile becomes visible in CI without
  byte-pinning repository policy.
- Fresh and legacy repositories can decline the feature without a perpetual
  warning, while an adopted repository cannot silently fall back to zero
  validated providers.
- Each provider needs its own parser contract and negative fixtures. That is
  more mechanism to maintain, but it keeps enforcement claims aligned with the
  provider matrix rather than forcing false uniformity.
- Adding a provider or changing its semantic floor requires a freshly stamped
  primary-source review and a versioned migration note.
