# ADR 009 — Declarative ship-manifest with a retirement contract

**Status:** accepted (v0.21.0)

## Context

Before v0.21.0, "which files does the kit ship, and what may update do to
each" was encoded four times: three shell-string lists inside
`install-lib.sh` (`_HARNESS_MECHANISM_TOPLEVEL`, `_HARNESS_POLICY_FILES`,
`_HARNESS_OPTIONAL_PROJECT_POLICY_TOPLEVEL`) plus a hand-maintained mirror of
the same set inside `check-harness.sh`'s completeness check (#9c). The hooks
tree shipped by a fifth mechanism (`cp -R` wholesale). A new shipped file
required editing code in two places; a file the kit *stopped* shipping could
not be expressed at all — update mode never removed anything, so the v0.20.0
suite split orphaned `scripts/test-install.sh` in the one existing install
and turned its audit red until a documented manual `rm`. That gap was the
recorded blocker for the adopter test descope plan.

## Decision

One declarative, shipped file — `scripts/kit-manifest` — is the SHIP
CONTRACT:

- Plain-text lines `<layer> <path>` (whitespace-separated, `#` comments,
  reserved trailing fields such as `dest=`), parseable by bash 3.2 `read`
  with no jq, per ADR 002's dependency floor.
- Layers: `mechanism` (replace-if-pristine), `policy` (diff-only even when
  pristine), `optional-policy` (authored per repo, pinned when present,
  diff-only), and `retired`.
- Every installer/manifest/checker function derives its file set from it:
  `harness_install_mechanism`, `harness_persist_base`,
  `harness_manifest_paths`, `harness_update_decision`,
  `harness_update_apply`, and check #9c. Hooks are enumerated per file like
  everything else; the integrity manifest still pins the hooks *tree* from
  the filesystem so repo-local hooks are pinned too.
- **Retirement**: `harness_update_apply` removes a `retired` path only when
  the installed copy is pristine (sha still matches its pin) and not
  ` # tailored`, reporting `remove`; drifted, tailored, or never-pinned
  copies are kept and reported `retire-keep`, and check #9d keeps WARNing
  while they linger. Retirement can never delete local changes.
- The kit-manifest is itself mechanism: sha-pinned in
  `scripts/.harness-manifest`, protected by `guard-config.sh`, and required
  on adopted repos by check #9d — it tells update what to overwrite and
  delete, which makes it the most security-sensitive shipped file after the
  integrity manifest.

Update mode always reads the NEW kit's copy: the incoming release defines
the current layering and the retired set.

## Consequences

- Shipping a new file is one added line; renames and descopes are a moved
  line plus a `retired` entry — the migration mechanism every later
  restructure phase (layout moves, test descope) rides on.
- The four duplicate encodings collapse; a fifth ad-hoc convention (wholesale
  hooks copy) goes with them.
- `guard-secrets.sh` reclassified policy → mechanism in the same release: its
  policy is fully externalized to `SECRET_PATTERNS` in `harness.conf`, so
  the generic script body upgrades like any other mechanism file
  (`test-install-update.sh` pins both directions of that boundary).
- A malicious or corrupted kit-manifest could direct update to overwrite or
  delete the wrong pristine files — hence pin + guard + #9d, and the
  pristine-only rule bounds the damage to files the kit itself installed.
- Pre-v0.21.0 installs lack the file; update installs it like any other
  newly-shipped mechanism file, and the manifest producers refuse to run
  without it rather than emitting an empty pin set.

Amends ADR 005 (the integrity manifest's concept is unchanged; its producer
and update's decision table are now kit-manifest-driven). See
[005-manifest-self-protection.md](005-manifest-self-protection.md).
