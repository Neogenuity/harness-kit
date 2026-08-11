#!/usr/bin/env bash
set -euo pipefail
cat > docs/service-registry.txt <<'EOF'
# Service registry (keys are uppercase and sorted)
ALPHA=api
BETA=worker
GAMMA=scheduler
EOF
