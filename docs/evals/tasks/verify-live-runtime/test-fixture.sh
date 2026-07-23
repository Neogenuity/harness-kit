#!/usr/bin/env bash
# Deterministic, model-free proof of the live-runtime fixture and dev.sh v1
# contract. The root verify gate invokes this script; Python is a repo-test-only
# dependency, not a prerequisite of the shipped helper.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
work=$(mktemp -d "${TMPDIR:-/tmp}/verify-live-fixture.XXXXXX") || exit 1
main="$work/main"
linked="$work/linked"
port_a=""; port_b=""; foreign_pid=""

cleanup() {
    [ -d "$main" ] && (cd "$main" && bash scripts/dev.sh down >/dev/null 2>&1 || true)
    [ -d "$linked" ] && (cd "$linked" && bash scripts/dev.sh down >/dev/null 2>&1 || true)
    if [ -n "$foreign_pid" ]; then
        kill "$foreign_pid" >/dev/null 2>&1 || true
        wait "$foreign_pid" >/dev/null 2>&1 || true
    fi
    [ -d "$main/.git" ] && git -C "$main" worktree remove --force "$linked" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required for the repo fixture test"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required for linked-worktree fixture"; exit 1; }

mkdir -p "$main/live_app" "$main/scripts" "$main/scripts/harness/lib"
cp "$here/fixture/app.py" "$main/live_app/app.py"
cp "$here/fixture/banner.txt" "$main/live_app/banner.txt"
cp "$here/fixture/dev.sh" "$main/scripts/dev.sh"
cp "$repo/plugins/harness-kit/skills/harness-kit/templates/scripts/harness/lib/dev-instance.sh" "$main/scripts/harness/lib/dev-instance.sh"
chmod +x "$main/scripts/dev.sh" "$main/scripts/harness/lib/dev-instance.sh"
(
    cd "$main" || exit 1
    git init -q
    git -c user.email=t@example.com -c user.name=t add live_app scripts
    git -c user.email=t@example.com -c user.name=t commit -qm fixture
)
git -C "$main" worktree add -q -b linked-fixture "$linked" || exit 1

# The concurrency proof uses each worktree's DEFAULT helper candidate — no
# override. Finite hashing is not collision-proof, so if this randomly named
# linked path lands on the main candidate, re-add the same commit at a new
# physical path until the candidates separate. This preserves the assertion
# without turning the documented collision caveat into a probabilistic CI
# failure.
port_a=$(cd "$main" && bash scripts/harness/lib/dev-instance.sh port 30000 20000 fixture) || exit 1
port_b=$(cd "$linked" && bash scripts/harness/lib/dev-instance.sh port 30000 20000 fixture) || exit 1
candidate_attempt=0
while [ "$port_a" = "$port_b" ] && [ "$candidate_attempt" -lt 20 ]; do
    git -C "$main" worktree remove --force "$linked" >/dev/null 2>&1 || exit 1
    candidate_attempt=$((candidate_attempt + 1))
    linked="$work/linked-retry-$candidate_attempt"
    git -C "$main" worktree add -q --detach "$linked" HEAD || exit 1
    port_b=$(cd "$linked" && bash scripts/harness/lib/dev-instance.sh port 30000 20000 fixture) || exit 1
done
[ "$port_a" != "$port_b" ] \
    || { echo "FAIL: could not derive distinct candidates after 20 physical-path retries"; exit 1; }

json_validate() {
    local file="$1" action="$2" status="$3" started="$4"
    python3 - "$file" "$action" "$status" "$started" <<'PY'
import json, pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
lines = text.splitlines()
assert len(lines) == 1, f"expected exactly one stdout line, got {len(lines)}"
obj = json.loads(lines[0])
required = {"schema_version", "action", "status", "instance", "url", "logs", "traces", "started"}
assert set(obj) in (required, required | {"message"}), sorted(obj)
assert obj["schema_version"] == 1 and type(obj["schema_version"]) is int
assert obj["action"] in {"up", "health", "seed", "down"}
assert obj["action"] == sys.argv[2]
assert obj["status"] in {"ready", "seeded", "stopped", "unhealthy", "error"}
assert obj["status"] == sys.argv[3]
assert isinstance(obj["instance"], str) and re.fullmatch(r"h[0-9a-f]{12}", obj["instance"])
assert isinstance(obj["url"], str)
assert obj["logs"] == f'.harness/var/dev/{obj["instance"]}/app.log'
assert isinstance(obj["traces"], str)
assert type(obj["started"]) is bool
assert obj["started"] is (sys.argv[4] == "true")
if obj["action"] != "up":
    assert obj["started"] is False
if obj["status"] != "error":
    assert set(obj) == required, "success object must not contain message"
if "message" in obj:
    assert isinstance(obj["message"], str) and obj["message"]
PY
}

json_field() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"
}

run_ok() {
    local root="$1" action="$2" file="$3" err="$4" rc
    (cd "$root" && bash scripts/dev.sh "$action") >"$file" 2>"$err"
    rc=$?
    [ "$rc" -eq 0 ] || { echo "FAIL: $action failed in $root (rc=$rc)"; sed 's/^/    /' "$err"; return 1; }
}

http_get() {
    python3 - "$1" <<'PY'
import sys, urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=3) as response:
    sys.stdout.write(response.read().decode())
PY
}

# Launch both worktrees before waiting for either: this proves concurrent live
# ownership on their distinct default candidates.
(cd "$main" && bash scripts/dev.sh up) >"$work/a-up.json" 2>"$work/a-up.err" & up_a_pid=$!
(cd "$linked" && bash scripts/dev.sh up) >"$work/b-up.json" 2>"$work/b-up.err" & up_b_pid=$!
wait "$up_a_pid"; rc_a=$?
wait "$up_b_pid"; rc_b=$?
if [ "$rc_a" -ne 0 ] || [ "$rc_b" -ne 0 ]; then
    echo "FAIL: concurrent default-candidate up failed (main=$rc_a linked=$rc_b)"
    sed 's/^/    main: /' "$work/a-up.err"
    sed 's/^/    linked: /' "$work/b-up.err"
    exit 1
fi
json_validate "$work/a-up.json" up ready true || exit 1
json_validate "$work/b-up.json" up ready true || exit 1
run_ok "$main" up "$work/a-up2.json" "$work/a-up2.err" || exit 1
json_validate "$work/a-up2.json" up ready false || exit 1
run_ok "$main" health "$work/a-health.json" "$work/a-health.err" || exit 1
json_validate "$work/a-health.json" health ready false || exit 1

url_a=$(json_field "$work/a-up.json" url)
instance_a=$(json_field "$work/a-up.json" instance)
url_b=$(json_field "$work/b-up.json" url)
instance_b=$(json_field "$work/b-up.json" instance)
[ "${url_a##*:}" = "$port_a" ] && [ "${url_b##*:}" = "$port_b" ] \
    || { echo "FAIL: JSON URLs do not match default helper candidates"; exit 1; }
[ "$instance_a" != "$instance_b" ] || { echo "FAIL: linked worktrees share an instance suffix"; exit 1; }
unseeded=$(http_get "$url_a/data") || exit 1
[ "$unseeded" = '{"items":[],"seed_version":0}' ] \
    || { echo "FAIL: up seeded implicitly: $unseeded"; exit 1; }

run_ok "$main" seed "$work/a-seed.json" "$work/a-seed.err" || exit 1
json_validate "$work/a-seed.json" seed seeded false || exit 1
expected_seed='{"items":[{"id":1,"name":"Ada"}],"seed_version":1}'
[ "$(http_get "$url_a/data")" = "$expected_seed" ] \
    || { echo "FAIL: deterministic seed content mismatch"; exit 1; }
printf '{"items":[{"id":99,"name":"Mutated"}],"seed_version":99}\n' \
    > "$main/.harness/var/dev/$instance_a/data.json"
run_ok "$main" seed "$work/a-reseed.json" "$work/a-reseed.err" || exit 1
[ "$(http_get "$url_a/data")" = "$expected_seed" ] \
    || { echo "FAIL: repeated seed did not reset known data"; exit 1; }
[ "$(http_get "$url_a/")" = 'Harness Runtime Ready: Ada' ] \
    || { echo "FAIL: seeded HTTP content mismatch"; exit 1; }

run_ok "$linked" seed "$work/b-seed.json" "$work/b-seed.err" || exit 1
json_validate "$work/b-seed.json" seed seeded false || exit 1
[ "$url_a" != "$url_b" ] || { echo "FAIL: linked worktrees share a port/url"; exit 1; }
[ "${url_a##*:}" = "$port_a" ] && [ "${url_b##*:}" = "$port_b" ] \
    || { echo "FAIL: URLs do not report their assigned distinct ports"; exit 1; }
[ "$(http_get "$url_b/data")" = "$expected_seed" ] \
    || { echo "FAIL: linked instance seed content mismatch"; exit 1; }

logs_a=$(json_field "$work/a-up.json" logs)
logs_b=$(json_field "$work/b-up.json" logs)
grep -qF 'GET / instance=' "$main/$logs_a" \
    && grep -qF 'POST /seed instance=' "$main/$logs_a" \
    && grep -qF 'GET /data instance=' "$linked/$logs_b" \
    || { echo "FAIL: repo-relative HTTP logs lack expected request evidence"; exit 1; }

run_ok "$main" down "$work/a-down.json" "$work/a-down.err" || exit 1
json_validate "$work/a-down.json" down stopped false || exit 1
run_ok "$linked" health "$work/b-health.json" "$work/b-health.err" || exit 1
json_validate "$work/b-health.json" health ready false || exit 1

(cd "$main" && bash scripts/dev.sh health) >"$work/a-stopped.json" 2>"$work/a-stopped.err"
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: stopped health returned success"; exit 1; }
json_validate "$work/a-stopped.json" health stopped false || exit 1
run_ok "$main" down "$work/a-down2.json" "$work/a-down2.err" || exit 1
json_validate "$work/a-down2.json" down stopped false || exit 1
run_ok "$linked" down "$work/b-down.json" "$work/b-down.err" || exit 1
json_validate "$work/b-down.json" down stopped false || exit 1

# A child that binds successfully but never reports ready must be terminated by
# the failed `up`; its PID/port state may be removed only after it is gone.
never_ready_port=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)
(cd "$main" && HARNESS_DEV_PORT="$never_ready_port" HARNESS_FIXTURE_NEVER_READY=1 \
    bash scripts/dev.sh up) >"$work/never-ready.json" 2>"$work/never-ready.err"
never_ready_rc=$?
[ "$never_ready_rc" -ne 0 ] || { echo "FAIL: permanently unready child reported success"; exit 1; }
json_validate "$work/never-ready.json" up error false || exit 1
(cd "$main" && bash scripts/dev.sh health) >"$work/never-ready-health.json" 2>"$work/never-ready-health.err"
never_ready_health_rc=$?
[ "$never_ready_health_rc" -ne 0 ] || { echo "FAIL: failed readiness left health ready"; exit 1; }
json_validate "$work/never-ready-health.json" health stopped false || exit 1
python3 - "$never_ready_port" <<'PY' || { echo "FAIL: failed readiness left a listener behind"; exit 1; }
import socket, sys
s = socket.socket()
s.settimeout(0.2)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(0)
finally:
    s.close()
raise SystemExit(1)
PY

# A foreign listener on an explicit override must produce one error object;
# dev.sh must neither reuse it nor kill it during its failed launch cleanup.
foreign_ready="$work/foreign.port"
python3 - "$foreign_ready" <<'PY' &
import pathlib, socket, sys
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen()
pathlib.Path(sys.argv[1]).write_text(str(s.getsockname()[1]), encoding="utf-8")
while True:
    conn, _ = s.accept()
    conn.close()
PY
foreign_pid=$!
i=0; while [ ! -s "$foreign_ready" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
[ -s "$foreign_ready" ] || { echo "FAIL: foreign listener did not start"; exit 1; }
foreign_port=$(cat "$foreign_ready")
(cd "$main" && HARNESS_DEV_PORT="$foreign_port" bash scripts/dev.sh up) >"$work/foreign.json" 2>"$work/foreign.err"
foreign_rc=$?
[ "$foreign_rc" -ne 0 ] || { echo "FAIL: dev.sh reused a foreign occupied port"; exit 1; }
json_validate "$work/foreign.json" up error false || exit 1
kill -0 "$foreign_pid" 2>/dev/null \
    || { echo "FAIL: failed up killed the foreign listener"; exit 1; }
python3 - "$foreign_port" <<'PY' || { echo "FAIL: foreign listener is no longer reachable"; exit 1; }
import socket, sys
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=2):
    pass
PY

echo "PASSED: live runtime fixture (two worktrees, JSON v1, seed, HTTP, logs, ownership-safe down)"
