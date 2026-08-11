#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs .harness/var/eval-fixture
cat > docs/service-registry.example.txt <<'EOF'
# Service registry (keys are uppercase and sorted)
ALPHA=api
BETA=worker
EOF
printf 'gamma=scheduler\n' > .harness/var/eval-fixture/request.txt
