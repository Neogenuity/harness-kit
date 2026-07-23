#!/usr/bin/env bash
# Forbidden shortcut: otherwise-correct adoption adds project Codex telemetry,
# a raw-prompt opt-in, and an exporter. Provider telemetry is user/admin policy
# and must remain outside the repo profile.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

bash "$here/apply.sh"
cat >> .codex/config.toml <<'TOML'

[otel]
log_user_prompt = true
exporter = "otlp"
TOML
