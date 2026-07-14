#!/usr/bin/env bash
# Conforming repo-specific dev lifecycle for the Python HTTP eval fixture.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "dev.sh: not inside a Git worktree" >&2
    exit 1
}
ROOT=$(cd "$ROOT" && pwd -P) || exit 1
HELPER="$ROOT/scripts/dev-instance.sh"
INSTANCE=$(bash "$HELPER" suffix fixture) || exit 1
STATE_REL=".harness/dev/$INSTANCE"
STATE="$ROOT/$STATE_REL"
PID_FILE="$STATE/pid"
PORT_FILE="$STATE/port"
DATA_REL="$STATE_REL/data.json"
DATA_FILE="$ROOT/$DATA_REL"
LOG_REL="$STATE_REL/app.log"
LOG_FILE="$ROOT/$LOG_REL"
TRACES_REL=""
PYTHON_BIN=${PYTHON_BIN:-python3}

emit() {
    local action="$1" status="$2" url="$3" started="$4" message="${5:-}"
    if [ -n "$message" ]; then
        printf '{"schema_version":1,"action":"%s","status":"%s","instance":"%s","url":"%s","logs":"%s","traces":"%s","started":%s,"message":"%s"}\n' \
            "$action" "$status" "$INSTANCE" "$url" "$LOG_REL" "$TRACES_REL" "$started" "$message"
    else
        printf '{"schema_version":1,"action":"%s","status":"%s","instance":"%s","url":"%s","logs":"%s","traces":"%s","started":%s}\n' \
            "$action" "$status" "$INSTANCE" "$url" "$LOG_REL" "$TRACES_REL" "$started"
    fi
}

state_port() {
    [ -f "$PORT_FILE" ] || return 1
    cat "$PORT_FILE"
}

state_pid() {
    [ -f "$PID_FILE" ] || return 1
    cat "$PID_FILE"
}

pid_running() {
    local pid
    pid=$(state_pid) || return 1
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null
}

ready() {
    local port url
    pid_running || return 1
    port=$(state_port) || return 1
    url="http://127.0.0.1:$port/health"
    "$PYTHON_BIN" - "$url" "$INSTANCE" <<'PY' >/dev/null 2>&1
import json, sys, urllib.request
with urllib.request.urlopen(sys.argv[1], timeout=1) as response:
    payload = json.load(response)
if payload != {"instance": sys.argv[2], "status": "ready"}:
    raise SystemExit(1)
PY
}

action="${1:-}"
[ "$#" -eq 1 ] || {
    echo "usage: bash scripts/dev.sh up|health|seed|down" >&2
    exit 64
}
case "$action" in up|health|seed|down) ;; *)
    echo "usage: bash scripts/dev.sh up|health|seed|down" >&2
    exit 64
esac

command -v "$PYTHON_BIN" >/dev/null 2>&1 || {
    emit "$action" error "" false "python3 is required"
    exit 1
}

case "$action" in
    up)
        if ready; then
            port=$(state_port)
            emit up ready "http://127.0.0.1:$port" false
            exit 0
        fi
        if pid_running; then
            port=$(state_port 2>/dev/null || true)
            url=""; [ -n "$port" ] && url="http://127.0.0.1:$port"
            emit up error "$url" false "recorded instance is running but not ready"
            exit 1
        fi
        if [ -n "${HARNESS_DEV_PORT:-}" ]; then
            port=$HARNESS_DEV_PORT
        else
            port=$(bash "$HELPER" port 30000 20000 fixture) || {
                emit up error "" false "could not derive a port"
                exit 1
            }
        fi
        case "$port" in ''|*[!0-9]*)
            emit up error "" false "HARNESS_DEV_PORT must be an integer"
            exit 1 ;;
        esac
        if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
            emit up error "" false "HARNESS_DEV_PORT must be between 1024 and 65535"
            exit 1
        fi
        mkdir -p "$STATE"
        touch "$LOG_FILE"
        printf '%s\n' "$port" > "$PORT_FILE"
        nohup "$PYTHON_BIN" "$ROOT/live_app/app.py" \
            --port "$port" --instance "$INSTANCE" --data "$DATA_FILE" --log "$LOG_FILE" \
            >> "$LOG_FILE" 2>&1 &
        launched_pid=$!
        printf '%s\n' "$launched_pid" > "$PID_FILE"
        i=0
        while [ "$i" -lt 50 ]; do
            if ready; then
                emit up ready "http://127.0.0.1:$port" true
                exit 0
            fi
            pid_running || break
            sleep 0.1
            i=$((i + 1))
        done
        # This PID is the child launched by this invocation, so it is safe to
        # terminate directly. Never erase the only ownership state while an
        # unready child is still alive: that would orphan the listener and make
        # later health/down calls falsely report stopped.
        kill "$launched_pid" 2>/dev/null || true
        wait "$launched_pid" 2>/dev/null || true
        rm -f "$PID_FILE" "$PORT_FILE"
        emit up error "" false "instance failed to become ready; inspect logs"
        exit 1
        ;;
    health)
        if ready; then
            port=$(state_port)
            emit health ready "http://127.0.0.1:$port" false
            exit 0
        fi
        if pid_running; then
            port=$(state_port 2>/dev/null || true)
            url=""; [ -n "$port" ] && url="http://127.0.0.1:$port"
            emit health unhealthy "$url" false
        else
            emit health stopped "" false
        fi
        exit 1
        ;;
    seed)
        if ! ready; then
            emit seed error "" false "instance must be ready before seed"
            exit 1
        fi
        port=$(state_port); url="http://127.0.0.1:$port"
        if "$PYTHON_BIN" - "$url/seed" <<'PY' >/dev/null 2>&1
import sys, urllib.request
request = urllib.request.Request(sys.argv[1], data=b"", method="POST")
with urllib.request.urlopen(request, timeout=2) as response:
    if response.status != 200:
        raise SystemExit(1)
PY
        then
            emit seed seeded "$url" false
            exit 0
        fi
        emit seed error "$url" false "deterministic seed failed"
        exit 1
        ;;
    down)
        if ! pid_running; then
            rm -f "$PID_FILE" "$PORT_FILE"
            emit down stopped "" false
            exit 0
        fi
        pid=$(state_pid)
        command_line=$(ps -p "$pid" -o command= 2>/dev/null || true)
        case "$command_line" in
            *"$ROOT/live_app/app.py"*"--instance $INSTANCE"*) ;;
            *)
                emit down error "" false "recorded pid is not owned by this worktree"
                exit 1 ;;
        esac
        kill "$pid" 2>/dev/null || true
        i=0
        while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do
            sleep 0.1
            i=$((i + 1))
        done
        if kill -0 "$pid" 2>/dev/null; then
            emit down error "" false "owned instance did not stop"
            exit 1
        fi
        rm -f "$PID_FILE" "$PORT_FILE"
        emit down stopped "" false
        ;;
esac
