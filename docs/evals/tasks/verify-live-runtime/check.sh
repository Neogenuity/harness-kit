#!/usr/bin/env bash
# End-state grader for verify-live-runtime. No browser gate: the headless eval
# runner provisions Python and HTTP only.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"

command -v python3 >/dev/null 2>&1 || { echo "python3 is required for this repo-only fixture"; exit 1; }
cmp -s scripts/dev.sh "$here/fixture/dev.sh" \
    || { echo "scripts/dev.sh changed; fix the application instead"; exit 1; }
cmp -s scripts/dev-instance.sh "$root/plugins/harness-kit/skills/harness-kit/templates/scripts/dev-instance.sh" \
    || { echo "scripts/dev-instance.sh changed; fix the application instead"; exit 1; }

# Grade workflow evidence before the grader starts its own process. A ready
# result means the agent leaked an instance; a missing retained log means it
# edited the obvious constant without exercising the live reproduce/re-run loop.
initial=$(bash scripts/dev.sh health 2>/dev/null); initial_rc=$?
[ "$initial_rc" -ne 0 ] || { echo "agent left the fixture running"; exit 1; }
initial_status=$(printf '%s' "$initial" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' 2>/dev/null) \
    || { echo "initial health returned invalid JSON"; exit 1; }
[ "$initial_status" = stopped ] || { echo "initial health must report stopped, got $initial_status"; exit 1; }
evidence_log=$(printf '%s' "$initial" | python3 -c '
import json,re,sys
o=json.load(sys.stdin)
assert o["action"] == "health" and o["status"] == "stopped"
assert re.fullmatch(r"\.harness/dev/h[0-9a-f]{12}/app\.log", o["logs"])
print(o["logs"])
' 2>/dev/null) || { echo "initial health did not report a valid repo-relative log"; exit 1; }
[ -f "$evidence_log" ] || { echo "missing retained live-flow log: $evidence_log"; exit 1; }
seed_count=$(grep -cF 'POST /seed instance=' "$evidence_log" || true)
get_count=$(grep -cF 'GET / instance=' "$evidence_log" || true)
[ "$seed_count" -ge 2 ] && [ "$get_count" -ge 2 ] \
    || { echo "retained log does not prove reproduce + rerun (seed=$seed_count GET=$get_count)"; exit 1; }

port=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)

cleanup() {
    HARNESS_DEV_PORT="$port" bash scripts/dev.sh down >/dev/null 2>&1 || true
}
trap cleanup EXIT

up=$(HARNESS_DEV_PORT="$port" bash scripts/dev.sh up 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] || { echo "fixture did not start"; exit 1; }
seed=$(HARNESS_DEV_PORT="$port" bash scripts/dev.sh seed 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] || { echo "fixture did not seed"; exit 1; }

url=$(printf '%s' "$up" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])' 2>/dev/null) \
    || { echo "up returned invalid JSON"; exit 1; }
status=$(printf '%s' "$seed" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' 2>/dev/null)
[ "$status" = seeded ] || { echo "seed did not report seeded"; exit 1; }

body=$(python3 - "$url/" <<'PY'
import sys, urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=3) as response:
    print(response.read().decode())
PY
) || { echo "GET / failed"; exit 1; }
printf '%s' "$body" | grep -qF 'Harness Runtime Ready: Ada' \
    || { echo "live content is still wrong: $body"; exit 1; }

health=$(HARNESS_DEV_PORT="$port" bash scripts/dev.sh health 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$health" | python3 -c '
import json, sys
o=json.load(sys.stdin)
assert o["action"] == "health" and o["status"] == "ready"
' >/dev/null 2>&1 || { echo "health is not ready after the fix"; exit 1; }

echo "ok: live seeded flow renders corrected content"
exit 0
