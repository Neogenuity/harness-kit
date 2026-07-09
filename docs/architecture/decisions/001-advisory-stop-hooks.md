# ADR 001 — Advisory stop-hooks never hard-block

**Status:** accepted (v0.2.0)

## Context

Stop-hooks fire when an agent believes it is finished — the natural place to
check project invariants ("new model isn't tenant-scoped", "route added but
not registered"). The obvious design is to block the stop until the agent
fixes the finding. In practice, blocking stop-hooks produce two failure
modes: agents loop against a check they cannot satisfy (burning tokens and
trust), and humans disable the hook the first time it wrongly blocks a
legitimate stop. A guard that gets disabled protects nothing.

## Decision

Stop-hooks in the kit are **advisory only**. `hook_advise_once` surfaces the
warning to the agent exactly once (via `decision: block` on the first stop,
with a loop guard that lets the second stop succeed), so the agent gets one
structured chance to self-correct and the run is never wedged. The
*enforcing* layer for any invariant is a test or a CI gate — something that
fails a build, not a conversation.

## Consequences

- An agent can ignore the warning. That is accepted: the same invariant must
  also exist as a test/CI check, or it is not an invariant.
- No run can be wedged by a buggy policy check, so policy checks are cheap
  to add and safe to experiment with.
- The one-shot mechanism needs per-provider loop guards (Claude Code
  `stop_hook_active`, Cursor followup semantics) — complexity the kit
  absorbs in `lib.sh` so policy authors never see it.
