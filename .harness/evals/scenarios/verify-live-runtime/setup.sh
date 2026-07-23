#!/usr/bin/env bash
# Install the self-contained live fixture, then plant the rendering regression.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"

mkdir -p live_app scripts
cp "$here/fixture/app.py" live_app/app.py
cp "$here/fixture/banner.txt" live_app/banner.txt
cp "$here/fixture/dev.sh" scripts/dev.sh
cp "$root/plugins/harness-kit/skills/harness-kit/templates/scripts/harness/lib/dev-instance.sh" scripts/harness/lib/dev-instance.sh
chmod +x scripts/dev.sh scripts/harness/lib/dev-instance.sh

printf 'Runtime Placeholder\n' > live_app/banner.txt
