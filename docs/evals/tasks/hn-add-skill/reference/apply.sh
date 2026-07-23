#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/skills/changelog
cat > docs/skills/changelog/SKILL.md <<'DOC'
---
name: changelog
description: >-
    Update CHANGELOG.md when cutting or preparing a release: add the version
    section, list user-facing changes first, and note any migration steps.
    Activates when asked to update the changelog, add release notes, or record
    what changed in a version.
---

# Changelog

Add a new version section at the top of `CHANGELOG.md`, above the previous
release. Lead with user-facing changes; follow with mechanism changes and their
migration notes. Keep the heading version in sync with the release.
DOC
awk '1; /docs\/skills\/release\/SKILL\.md/ && !done {
  print "- [docs/skills/changelog/SKILL.md](docs/skills/changelog/SKILL.md) — update the changelog when cutting a release";
  done=1 }' AGENTS.md > AGENTS.md.tmp && mv AGENTS.md.tmp AGENTS.md
bash scripts/harness/sync >/dev/null
