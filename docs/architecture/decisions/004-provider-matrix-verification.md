# ADR 004 — Per-fact verification stamps in the provider matrix

**Status:** accepted (v0.2.0)

## Context

The kit's provider matrix records, per harness, where files live, which hook
events exist, and what their payloads look like. These facts change under
our feet — hook APIs are the least stable surface in every coding agent —
and they are exactly the kind of plausible-sounding detail an LLM (or a
tired human) will confidently hallucinate. A reference doc about
fast-moving tools that doesn't carry its own freshness metadata is a
hallucination amplifier: agents read it and act on stale facts with full
confidence.

## Decision

Load-bearing facts in
[provider-matrix.md](../../../plugin/skills/harness-kit/references/provider-matrix.md)
carry a **verified stamp** — a validated date, cross-referenced to the file's
Sources section — recorded as each fact is individually checked. The header
states how current the matrix is overall, and facts that haven't been
re-verified are surfaced as such rather than presented with false
confidence. Stamping the remaining unstamped facts (the capability table) is
tracked as a release-checklist item; the discipline is that a fact you add or
change gets a stamp, not that the whole file is stamped at once. Known-unstable
facts (e.g. Codex hooks being experimental/flag-gated) are labeled with their
stability, not just their current value.

## Consequences

- The matrix is more expensive to maintain — the cost is deliberate and
  visible, which is the point.
- Consumers (human or agent) can judge staleness from a fact's own stamp,
  or from the header where a fact isn't individually stamped yet, instead of
  trusting the file wholesale.
- The same discipline the kit asks of target repos ("docs the agent can
  trust") is applied to the kit's own most perishable document.
