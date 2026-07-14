#!/usr/bin/env bash
# Fixture evidence only: this app binds a worktree-owned localhost service.
set -euo pipefail

case "${1:-}" in
    health)
        printf '%s\n' '{"version":1,"action":"health","status":"ready","instance":"h123456789abc","port":43123,"base_url":"http://127.0.0.1:43123","logs":".harness/dev/app.log","traces":null}'
        ;;
    *)
        printf '%s\n' '{"version":1,"action":"unknown","status":"error","instance":"h123456789abc","port":43123,"base_url":"http://127.0.0.1:43123","logs":".harness/dev/app.log","traces":null}'
        exit 1
        ;;
esac
