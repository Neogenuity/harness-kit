#!/usr/bin/env bash
# Reference solution: what a known-good agent produces. Run in the workspace.
set -euo pipefail
mkdir -p docs/conventions
cat > docs/conventions/error-handling.md <<'DOC'
# Error Handling

Fail loud at boundaries and quiet in the core. Validate and normalize every
external input at the edge, raise typed errors with actionable messages, and
never swallow an exception without logging its context. User-facing surfaces
show a safe summary; logs carry the detail.
DOC
# Insert a bullet immediately after the existing templates.md convention bullet.
awk '1; /docs\/conventions\/templates\.md/ && !done {
  print "- [docs/conventions/error-handling.md](docs/conventions/error-handling.md) — how this project handles and surfaces errors";
  done=1 }' AGENTS.md > AGENTS.md.tmp && mv AGENTS.md.tmp AGENTS.md
