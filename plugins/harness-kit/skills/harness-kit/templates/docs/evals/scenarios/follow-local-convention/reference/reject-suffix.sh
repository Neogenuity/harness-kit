#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "$0")/apply.sh"
printf 'OMEGA=conflict\n' >> docs/service-registry.txt
printf 'GAMMA=changed-reference\n' >> docs/service-registry.example.txt
