#!/usr/bin/env bash
# Project gate: fail if the NEEDS_WORK marker remains anywhere under notes/.
set -uo pipefail
if grep -rq 'NEEDS_WORK' notes/ 2>/dev/null; then
    echo "gate-todo: unresolved NEEDS_WORK marker under notes/" >&2
    exit 1
fi
echo "gate-todo: clean"
