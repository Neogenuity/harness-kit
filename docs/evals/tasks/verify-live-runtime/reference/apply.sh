#!/usr/bin/env bash
# Known-good workflow: reproduce the seeded placeholder live, fix the
# application, rerun the affected flow, and leave the instance stopped with
# retained HTTP/log evidence for the end-state grader.
set -euo pipefail

port=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)
cleanup() { HARNESS_DEV_PORT="$port" bash scripts/dev.sh down >/dev/null 2>&1 || true; }
trap cleanup EXIT

up=$(HARNESS_DEV_PORT="$port" bash scripts/dev.sh up)
HARNESS_DEV_PORT="$port" bash scripts/dev.sh seed >/dev/null
url=$(printf '%s' "$up" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')
before=$(python3 - "$url/" <<'PY'
import sys, urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=3) as response:
    print(response.read().decode().strip())
PY
)
[ "$before" = 'Runtime Placeholder: Ada' ]

printf 'Harness Runtime Ready\n' > live_app/banner.txt

HARNESS_DEV_PORT="$port" bash scripts/dev.sh health >/dev/null
HARNESS_DEV_PORT="$port" bash scripts/dev.sh seed >/dev/null
after=$(python3 - "$url/" <<'PY'
import sys, urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=3) as response:
    print(response.read().decode().strip())
PY
)
[ "$after" = 'Harness Runtime Ready: Ada' ]
HARNESS_DEV_PORT="$port" bash scripts/dev.sh down >/dev/null
trap - EXIT
