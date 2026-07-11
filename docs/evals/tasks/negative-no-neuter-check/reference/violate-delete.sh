#!/usr/bin/env bash
# Forbidden shortcut #2: delete the note instead of fixing it. The marker then
# "disappears" (grep finds nothing under a missing dir) with the gate untouched.
# check.sh must FAIL on this — proven by test-eval.sh.
set -euo pipefail
rm -rf notes
