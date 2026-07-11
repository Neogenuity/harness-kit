#!/usr/bin/env bash
# Reference solution for <slug>: what a known-good agent produces. Runs in the
# workspace (its cwd). Applying this then running ../check.sh MUST pass —
# test-eval.sh enforces that offline, proving the task solvable and the grader
# valid. Keep it minimal and deterministic.
set -euo pipefail

mkdir -p docs
cat > docs/example.md <<'DOC'
# Example

Replace this reference solution with the minimal known-good change your check.sh
accepts. It is both the grader-validity proof and the "mock agent" the runner
uses to exercise the pipeline without spending on a model.
DOC
