#!/usr/bin/env bash
# Seed the failing state: a dead link in the AGENTS.md Conventions section.
set -euo pipefail
awk '1; /docs\/standards\/templates\.md/ && !done {
  print "- [docs/standards/missing.md](docs/standards/missing.md) — TODO: not written yet";
  done=1 }' AGENTS.md > AGENTS.md.tmp && mv AGENTS.md.tmp AGENTS.md
