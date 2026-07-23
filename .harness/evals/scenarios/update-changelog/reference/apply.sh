#!/usr/bin/env bash
set -euo pipefail
# Insert an Unreleased section immediately before the first '## 0.' heading.
awk '
  /^## 0\./ && !done {
    print "## Unreleased";
    print "";
    print "- Placeholder: describe the next change here before cutting a release.";
    print "";
    done=1
  }
  { print }
' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
