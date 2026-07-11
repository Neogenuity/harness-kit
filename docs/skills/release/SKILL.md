---
name: release
description: >-
    Cut a harness-kit release: run the quality gates, bump the plugin
    version, update the changelog, refresh this repo's own installed harness
    and manifest, and tag. Activates when asked to release, publish, cut,
    or tag a new version of harness-kit, or to prepare a version bump.
---

# Release

Ship a new plugin version. "Done" means: gates green, version bumped,
changelog entry written, the root dogfood installation upgraded to match the
templates being shipped, and an annotated tag pushed.

## Prerequisites

- Read [docs/conventions/templates.md](../../conventions/templates.md) —
  especially version discipline.
- Working tree clean apart from the release changes; `main` up to date.

## Steps

1. `bash scripts/verify.sh` — all gates green before anything else.
2. Decide the version (semver: mechanism behavior or template layout changes
   are at least minor while pre-1.0). `plugins/harness-kit/VERSION` is the
   single source of truth — set it there, and set the same value in **both**
   `plugins/harness-kit/.claude-plugin/plugin.json` and
   `plugins/harness-kit/.codex-plugin/plugin.json`. `scripts/check-packaging.sh`
   (the `verify.sh` manifests gate) fails unless all three agree (see ADR 007).
3. Add the `CHANGELOG.md` entry: user-facing changes first, mechanism
   changes with their migration note (does update mode replace the file, or
   diff it?).
4. Sweep `README.md` and any status docs for version references that would
   go stale — README must not carry a hardcoded kit version (see Common
   Mistakes).
5. If `plugins/harness-kit/skills/harness-kit/templates/scripts/` changed since the last
   release, roll the changes into this repo's own installation (the kit's
   **update** mode: replace manifest-matching files in `scripts/`, diff
   tailored ones), then re-pin `scripts/.harness-manifest` with the new
   version header and checksums (command in the SKILL's init step 8; set
   `HARNESS_ALLOW_MECHANISM_EDITS=1` for the session). This step is
   CI-enforced: `scripts/test-template-sync.sh` fails when a non-tailored
   installed file differs from its template.
6. `bash scripts/verify.sh` again — the manifest gate must pass post-re-pin.
7. Commit `release: v<version>`, tag `v<version>` (annotated), push with
   `--follow-tags`.

## Verification

- `bash scripts/verify.sh` passes on the release commit.
- `git show v<version>` shows the tag on the release commit.
- `plugins/harness-kit/VERSION`, both plugin.json versions, the manifest
  header, and the CHANGELOG heading all state the same version
  (`check-packaging.sh` enforces the manifest trio).
- `grep -nE '\bv?[0-9]+\.[0-9]+\.[0-9]+' README.md` returns no kit-version
  claims that contradict `plugins/harness-kit/VERSION` (install-command
  examples and provider version stamps are fine).

## Common Mistakes

- Re-pinning the manifest *before* rolling template changes into `scripts/`
  — the pin then blesses the stale copy and CI goes green on a lie.
- Bumping only one version field — the version lives in
  `plugins/harness-kit/VERSION` and must be mirrored into both plugin.json
  files; the packaging gate fails on any mismatch.
- Forgetting `--follow-tags`, so the marketplace serves the new version but
  the tag never reaches the remote.
- Letting README go stale — a hardcoded `v0.6.0` sat in README's Status
  section through two releases because no step owned sweeping it; README
  now points at `plugins/harness-kit/VERSION` instead of a literal version.
