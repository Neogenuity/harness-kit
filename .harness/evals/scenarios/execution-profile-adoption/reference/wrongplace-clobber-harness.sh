#!/usr/bin/env bash
# Forbidden shortcut: replace canonical harness policy/TOC/runtime evidence
# with only the newly requested profile artifacts.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

bash "$here/apply.sh"
printf '%s\n' 'EXECUTION_PROFILE_PROVIDERS=".claude .codex"' > scripts/harness/harness.conf
printf '%s\n' '- [docs/conventions/execution-profiles.md](docs/conventions/execution-profiles.md)' > AGENTS.md
cat > scripts/dev.sh <<'SH'
#!/usr/bin/env bash
echo replaced
SH
chmod +x scripts/dev.sh
