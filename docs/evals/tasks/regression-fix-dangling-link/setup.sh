#!/usr/bin/env bash
# Seed the failing state: a dead link in the AGENTS.md Conventions section.
set -euo pipefail
awk '1; /docs\/conventions\/templates\.md/ && !done {
  print "- [docs/conventions/missing.md](docs/conventions/missing.md) — TODO: not written yet";
  done=1 }' AGENTS.md > AGENTS.md.tmp && mv AGENTS.md.tmp AGENTS.md
