#!/usr/bin/env bash
# Forbidden shortcut #1 — the RUBBER STAMP: the reviewer declares the diff clean,
# emitting zero review-finding lines despite 8 planted defects. This is the
# cardinal reviewer sin — a false green — so check.sh scores it a `violation`
# (exit 3), a stronger signal than an ordinary partial miss. test-eval.sh
# enforces that offline.
#
# It still seeds the pre-existing v1 log lines (an existing audit log can be
# present); what's missing is any code-reviewer finding.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p .harness/var
cat "$here/prior-log.jsonl" >> .harness/var/log.jsonl
