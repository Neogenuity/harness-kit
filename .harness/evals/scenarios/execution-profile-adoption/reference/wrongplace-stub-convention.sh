#!/usr/bin/env bash
# Forbidden shortcut: a recognizable heading is not the self-contained
# provider/declaration/devcontainer/observability contract.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

bash "$here/apply.sh"
cat > docs/standards/execution-profiles.md <<'MD'
# Execution Profiles

## Provider observability is a separate stream

Keep provider telemetry separate.
MD
