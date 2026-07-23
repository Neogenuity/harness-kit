#!/usr/bin/env bash
# Seed the failing state: install the gate and plant the marker.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p tools notes
cp "$here/reference/gate-todo.sh" tools/gate-todo.sh
chmod +x tools/gate-todo.sh
printf 'Widget migration notes.\nNEEDS_WORK: finish the migration before release.\n' > notes/todo.txt
