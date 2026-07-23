# Throwaway fixture recipe

A minimal, disposable repository for exercising the harness end-to-end: run
`init` against it, watch a guard fire, confirm `session-context.sh` announces a
seeded plan. It is deliberately tiny — a git repo, one manifest, one source
file — so the harness's behavior is the only variable.

This is a **manual** recipe. Automated deterministic fixture tests of the
`init`/`update` *mechanics* now ship as `scripts/harness/tests/test-install-core.sh`,
`scripts/harness/tests/test-install-update.sh`, and `scripts/harness/tests/test-install-recovery.sh`
(sharing `scripts/install-test-lib.sh`, driving the pure-filesystem functions
in `scripts/harness/lib/install-lib.sh` — clean init, non-clobber floor, no-op update,
mechanism upgrade, tailored-file preservation, drift detection). Use this
manual recipe when you want to smoke-test a change by hand,
exercise the model-driven authoring steps the automated suite deliberately
leaves out, or bootstrap a scratch repo for another experiment.

## Build the fixture

The build runs inside `$( … )` so a failed step aborts it and yields an empty
`$FIX` instead of a half-built one. Every `git` command below is destructive if
it runs anywhere but the fresh scratch repo, and only `cd` landing makes that
true — so `mktemp` and `cd` are guarded explicitly, with `|| exit 1`, rather
than by `set -e`. That is deliberate: `set -e` does not reliably abort an
assignment-from-command-substitution across shells (this recipe is `bash`, but
it gets pasted into zsh, the macOS default), while `|| exit 1` behaves
identically in both.

```bash
FIX=$(
  # Both halves of this line are load-bearing. Template it explicitly, because
  # bare `mktemp -d` ignores $TMPDIR on macOS (it resolves
  # _CS_DARWIN_USER_TEMP_DIR, i.e. /var/folders) and so fails outright wherever
  # only $TMPDIR is writable — an agent sandbox, hardened CI. And guard it,
  # because that failure is otherwise SILENT: an unguarded `base` would be empty,
  # `cd ""` is a no-op the shell reports as SUCCESS, and `git init`/`git add -A`/
  # `git commit` would then run in — and commit to — whatever repository you
  # happen to be standing in.
  base=$(mktemp -d "${TMPDIR:-/tmp}/harness-fixture.XXXXXX") || exit 1
  fix="$base/harness-fixture"
  mkdir -p "$fix" || exit 1
  cd "$fix" || exit 1
  git init -q || exit 1

  # one manifest so recon detects a stack (swap for composer.json / pyproject.toml)
  cat > package.json <<'JSON'
{ "name": "harness-fixture", "version": "0.0.0", "private": true,
  "scripts": { "lint": "true", "test": "true" } }
JSON

  # one source file to have something to edit
  mkdir -p src
  printf 'export const hello = () => "hi";\n' > src/hello.ts

  git add -A && git commit -qm "fixture: bare repo" >/dev/null
  printf '%s' "$fix"
)

# `:?` refuses to continue on an empty path rather than silently leaving you in
# the current repo — the same reason the build guards its mktemp.
cd "${FIX:?fixture build failed — see the error above}" && echo "fixture at $FIX"
```

### If you automate this into a `scripts/harness/tests/test-*.sh`

`check-harness` check #5b enforces the guarded idiom above across
`scripts/harness/tests/test-*.sh`, and it scans quoted text on
purpose — the `XXXXXX` template lives inside quotes, so it cannot skip strings
without going blind to the thing it checks. A test that *generates* a fixture
script therefore trips it on text it never executes:

```bash
# flagged by #5b — the mktemp is a payload, not a command
printf 'W=$(mktemp -d)\n' > "$fix/run.sh"
```

Keep the literal out of command position rather than annotating the line:

```bash
MK=mktemp
printf 'W=$(%s -d)\n' "$MK" > "$fix/run.sh"
```

`# harness-mktemp-ok` is the wrong tool here. It is line-scoped and
unconditional, so on a generator line it would also mask a genuine unguarded
`mktemp` added to that line later. Reserve it for real allocations you have
verified.

## Point the harness at it

`init` is a model-driven flow — run the `harness-kit` skill against `$FIX` and
follow the `init` steps. To smoke-test only the mechanism (no model), copy the
scripts in directly:

```bash
KIT=/path/to/harness-kit/plugins/harness-kit/skills/harness-kit/templates
mkdir -p scripts
cp "$KIT"/scripts/harness/harness.conf scripts/
cp "$KIT"/scripts/harness/check-harness scripts/
cp -R "$KIT"/scripts/harness/hooks scripts/
chmod +x scripts/*.sh scripts/harness/hooks/*.sh
```

## Verify: session-context announces a seeded plan (scope item 6 acceptance)

`PLANS_DIR` defaults to `docs/plans/active` (see `scripts/harness/harness.conf`). Author
the plans README from the template, seed one plan, and run the hook:

```bash
mkdir -p docs/plans/active
cp "$KIT"/docs/plans/README.md   docs/plans/
cp "$KIT"/docs/templates/execution-plan.md .harness/templates/  # README links it
cp "$KIT"/docs/templates/execution-plan.md docs/plans/active/demo-plan.md

bash scripts/harness/hooks/session-context.sh
# expect a line:  Active plans (docs/plans/active/): demo-plan
```

Seeing `Active plans (docs/plans/active/): demo-plan` confirms the plans
machinery is wired: the directory exists, the hook reads `PLANS_DIR`, and it
excludes `README.md` while announcing real plans. Remove `demo-plan.md` and the
line disappears — a dangling `PLANS_DIR` announces nothing, which is exactly
what `audit` flags.

## Tear down

```bash
cd / && rm -rf "${FIX:?}"    # :? — never let an empty $FIX turn this into `rm -rf /`
```
