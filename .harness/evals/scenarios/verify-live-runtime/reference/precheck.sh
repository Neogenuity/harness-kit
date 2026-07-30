#!/usr/bin/env bash
# Host prerequisites for this task's grader-validity check (test-eval-graders).
#
# reference/apply.sh drives scripts/dev.sh, whose fixture app is python3 and
# which must bind a loopback port. Neither is guaranteed on a host that can
# otherwise run the whole shipped floor: Git for Windows bundles no python at
# all, and an agent sandbox commonly denies bind(). Without this probe the
# suite reported
#
#     FAIL: verify-live-runtime: reference/apply.sh errored
#
# which reads as "the eval bank is broken" and sends triage to the grader, when
# the honest answer is that the host cannot host the task.
#
# Exit 0 = this host can run the task. Non-zero, with the reason on stdout, =
# skip it. The reason is quoted verbatim in the SKIP line, so keep it short and
# name the missing capability rather than the symptom.
#
# NOT a substitute for the grader: a host that passes this probe still runs the
# full reference-scores-pass check. This only decides whether the task can run
# here at all.
set -u

command -v python3 >/dev/null 2>&1 || {
    echo "python3 not on PATH (the dev.sh fixture app is python3)"
    exit 1
}

# One probe covers both remaining prerequisites: it needs python3 to execute at
# all, and it fails closed when bind() is denied. Port 0 lets the kernel pick,
# so this never collides with a real service or with a parallel gate.
#
# `python3 -c "$var"` rather than a heredoc: `cmd <<'PY' || { ... }` is not
# parseable (SC1073), and splitting it into an if/then around a heredoc puts the
# program text between the condition and its body, which reads worse than this.
# The program distinguishes "bind was refused" (exit 1 — a real host decline)
# from "this probe is broken" (exit 3 — a NameError/AttributeError from a typo
# in the lines below). Without that split every Python failure collapses to
# exit 1 and a typo'd probe reads as a legitimate decline, silently retiring
# this task's grader coverage. It is not total: a SyntaxError is raised before
# the try block runs and still exits 1. Narrower, not solved.
bind_probe='import socket, sys
try:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    s.close()
except OSError:
    sys.exit(1)
except Exception:
    sys.exit(3)'
python3 -c "$bind_probe" 2>/dev/null; bind_rc=$?
case "$bind_rc" in
    0) ;;
    1) echo "cannot bind a loopback port (sandboxed?)"; exit 1 ;;
    *) echo "bind probe itself failed (exit $bind_rc) — fix precheck.sh"; exit 3 ;;
esac
