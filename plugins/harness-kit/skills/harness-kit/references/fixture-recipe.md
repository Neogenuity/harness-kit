# Throwaway fixture recipe

A minimal, disposable repository for exercising the harness end-to-end: run
`init` against it, watch a guard fire, confirm `session-context.sh` announces a
seeded plan. It is deliberately tiny — a git repo, one manifest, one source
file — so the harness's behavior is the only variable.

This is a **manual** recipe. Automated deterministic fixture tests of the
`init`/`update` *mechanics* now ship as `scripts/test-install.sh` (driving the
pure-filesystem functions in `scripts/install-lib.sh` — clean init, non-clobber
floor, no-op update, mechanism upgrade, tailored-file preservation, drift
detection). Use this manual recipe when you want to smoke-test a change by hand,
exercise the model-driven authoring steps the automated suite deliberately
leaves out, or bootstrap a scratch repo for another experiment.

## Build the fixture

```bash
FIX="$(mktemp -d)/harness-fixture"
mkdir -p "$FIX" && cd "$FIX"
git init -q

# one manifest so recon detects a stack (swap for composer.json / pyproject.toml)
cat > package.json <<'JSON'
{ "name": "harness-fixture", "version": "0.0.0", "private": true,
  "scripts": { "lint": "true", "test": "true" } }
JSON

# one source file to have something to edit
mkdir -p src
printf 'export const hello = () => "hi";\n' > src/hello.ts

git add -A && git commit -qm "fixture: bare repo"
echo "fixture at $FIX"
```

## Point the harness at it

`init` is a model-driven flow — run the `harness-kit` skill against `$FIX` and
follow the `init` steps. To smoke-test only the mechanism (no model), copy the
scripts in directly:

```bash
KIT=/path/to/harness-kit/plugins/harness-kit/skills/harness-kit/templates
mkdir -p scripts
cp "$KIT"/scripts/harness.conf scripts/
cp "$KIT"/scripts/check-harness.sh scripts/
cp -R "$KIT"/scripts/hooks scripts/
chmod +x scripts/*.sh scripts/hooks/*.sh
```

## Verify: session-context announces a seeded plan (scope item 6 acceptance)

`PLANS_DIR` defaults to `docs/plans/active` (see `scripts/harness.conf`). Author
the plans README from the template, seed one plan, and run the hook:

```bash
mkdir -p docs/plans/active
cp "$KIT"/docs/plans/README.md   docs/plans/
cp "$KIT"/docs/plans/_template.md docs/plans/            # README links it
cp "$KIT"/docs/plans/_template.md docs/plans/active/demo-plan.md

bash scripts/hooks/session-context.sh
# expect a line:  Active plans (docs/plans/active/): demo-plan
```

Seeing `Active plans (docs/plans/active/): demo-plan` confirms the plans
machinery is wired: the directory exists, the hook reads `PLANS_DIR`, and it
excludes `README.md` while announcing real plans. Remove `demo-plan.md` and the
line disappears — a dangling `PLANS_DIR` announces nothing, which is exactly
what `audit` flags.

## Tear down

```bash
cd / && rm -rf "$FIX"
```
