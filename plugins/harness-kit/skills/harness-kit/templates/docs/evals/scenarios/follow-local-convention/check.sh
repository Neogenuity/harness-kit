#!/usr/bin/env bash
set -uo pipefail
[ -f docs/service-registry.txt ] || { echo "missing docs/service-registry.txt"; exit 1; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/follow-local-convention.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/registry" <<'EOF'
# Service registry (keys are uppercase and sorted)
ALPHA=api
BETA=worker
GAMMA=scheduler
EOF
cat > "$WORK/example" <<'EOF'
# Service registry (keys are uppercase and sorted)
ALPHA=api
BETA=worker
EOF
cmp -s docs/service-registry.txt "$WORK/registry" \
    || { echo "registry does not exactly follow the local sorted uppercase convention"; exit 1; }
cmp -s docs/service-registry.example.txt "$WORK/example" \
    || { echo "reference example changed"; exit 1; }
echo ok
