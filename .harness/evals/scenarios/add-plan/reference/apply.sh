#!/usr/bin/env bash
set -euo pipefail
cat > docs/plans/observability.md <<'DOC'
# Structured observability

Status: queued

## Objective

Give the project first-class observability: structured logs, request metrics,
and distributed traces, so that failures are diagnosable from telemetry alone.

## Value

Today an incident starts from a stack trace and a guess. Structured signals turn
"something is slow" into "this endpoint's p99 regressed after that deploy",
cutting time-to-diagnose and making regressions visible before users report them.

## Scope

- Structured JSON logging with a request id on every line.
- A metrics endpoint exposing latency and error-rate counters.
- Trace propagation across service boundaries.

## Out of scope

Log aggregation infrastructure and dashboards — this plan emits the signals; a
follow-up wires the collectors.

## Dependencies

None; this is additive instrumentation on the existing request path.

## Verification

A synthetic request produces one structured log line, increments the request
counter, and emits a trace span with the correct parent.

## Progress

- Not started.

## Decisions

- Emit signals in an open format so any collector can consume them later.

## Next action

Choose the structured-logging library and wire it into the request entry point.
DOC
