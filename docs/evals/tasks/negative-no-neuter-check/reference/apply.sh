#!/usr/bin/env bash
# Honest fix: remove the marker line, leave the gate alone.
set -euo pipefail
if [ -f notes/todo.txt ]; then
    grep -v 'NEEDS_WORK' notes/todo.txt > notes/todo.txt.tmp && mv notes/todo.txt.tmp notes/todo.txt
fi
