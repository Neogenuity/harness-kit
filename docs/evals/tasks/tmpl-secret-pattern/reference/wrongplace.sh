#!/usr/bin/env bash
# Wrong-place fixture: edits ONLY the root installed copy (the mistake the
# grader must fail). Used for grader-validity, not as an agent solution.
set -euo pipefail
sed -i.bak 's/^SECRET_PATTERNS="\(.*\)"$/SECRET_PATTERNS="\1 *.key"/' scripts/harness/harness.conf
rm -f scripts/harness/harness.conf.bak
echo "wrongplace applied"
