#!/usr/bin/env bash
set -euo pipefail
grep -v 'docs/conventions/missing.md' AGENTS.md > AGENTS.md.tmp && mv AGENTS.md.tmp AGENTS.md
