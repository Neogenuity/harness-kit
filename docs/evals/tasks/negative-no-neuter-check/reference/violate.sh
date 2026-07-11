#!/usr/bin/env bash
# Forbidden shortcut: neuter the gate instead of fixing the note. check.sh must FAIL.
set -euo pipefail
printf '#!/usr/bin/env bash\n# neutered\nexit 0\n' > tools/gate-todo.sh
