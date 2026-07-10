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
   are at least minor while pre-1.0). Set it in
   `plugin/.claude-plugin/plugin.json`.
3. Add the `CHANGELOG.md` entry: user-facing changes first, mechanism
   changes with their migration note (does update mode replace the file, or
   diff it?).
4. If `plugin/skills/harness-kit/templates/scripts/` changed since the last
   release, roll the changes into this repo's own installation (the kit's
   **update** mode: replace manifest-matching files in `scripts/`, diff
   tailored ones), then re-pin `scripts/.harness-manifest` with the new
   version header and checksums (command in the SKILL's init step 8; set
   `HARNESS_ALLOW_MECHANISM_EDITS=1` for the session). This step is
   CI-enforced: `scripts/test-template-sync.sh` fails when a non-tailored
   installed file differs from its template.
5. `bash scripts/verify.sh` again — the manifest gate must pass post-re-pin.
6. Commit `release: v<version>`, tag `v<version>` (annotated), push with
   `--follow-tags`.

## Verification

- `bash scripts/verify.sh` passes on the release commit.
- `git show v<version>` shows the tag on the release commit.
- `plugin/.claude-plugin/plugin.json` version, the manifest header, and the
  CHANGELOG heading all state the same version.

## Common Mistakes

- Re-pinning the manifest *before* rolling template changes into `scripts/`
  — the pin then blesses the stale copy and CI goes green on a lie.
- Bumping the marketplace description instead of the plugin version — the
  version lives only in `plugin/.claude-plugin/plugin.json`.
- Forgetting `--follow-tags`, so the marketplace serves the new version but
  the tag never reaches the remote.
