# AI Agent Instructions

This file is the **table of contents** for the repository knowledge base. All
detailed documentation lives in `docs/`. Start here, then follow links to
deeper sources.

## Project

**harness-kit** — a Claude Code skill/plugin that scaffolds a standardized
cross-agent harness (Claude Code, Cursor, Codex, OpenCode, `.agents`) into
any repository. Two facts to know before touching anything:

1. The distributed plugin lives entirely under `plugins/harness-kit/` — everything at the
   repo root is this repo's **own installed harness** (dogfooding) and never
   ships to users.
2. `plugins/harness-kit/skills/harness-kit/templates/` is the product. The root
   `scripts/` are an *installed, tailored copy* of those templates, pinned by
   `scripts/.harness-manifest`. Improve the templates first, then roll the
   change into the installed copy via the kit's update mode.

## Architecture

- [docs/architecture/ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md) — repo anatomy: marketplace root, `plugins/harness-kit/` distribution, the self-installed harness and its upgrade loop
- [docs/architecture/decisions/README.md](docs/architecture/decisions/README.md) — decision records: the "why" behind the pattern's load-bearing choices

## Conventions

- [docs/conventions/templates.md](docs/conventions/templates.md) — rules for editing the shipped templates: TAILOR blocks, tests-with-guards, stub caps, provider-matrix citation discipline

## Skills (Task Workflows)

- [docs/skills/release/SKILL.md](docs/skills/release/SKILL.md) — cut a release: version bump, changelog, manifest re-pin, tag

The per-harness copies (`.claude/skills/`, `.cursor/skills/`,
`.opencode/skills/`, `.agents/skills/` — Codex reads `.agents/skills/`) are
**generated** pointer stubs. Edit the canonical file here, then run
`bash scripts/sync-agent-skills.sh`; `check-harness.sh` (CI-gated) fails if
stubs drift from the generator output.

## Plans

- [docs/plans/README.md](docs/plans/README.md) — execution-plan lifecycle (queued → active → completed) and the ordered roadmap to 1.0; plans in `docs/plans/active/` are announced at session start

## Evals

- [docs/evals/README.md](docs/evals/README.md) — behavioral golden tasks that measure whether the harness changes agent behavior: multi-trial pass@k/pass^k over isolated workspaces (`scripts/eval.sh`), regression scoring vs recorded baselines (`scripts/eval-harness.sh`), grader validity pinned offline by `scripts/test-eval.sh`

## Quality Gates

The ordered gates live in **`scripts/verify.sh`** — the executable definition
of "done". Run it before any task is complete:

```bash
bash scripts/verify.sh          # every gate (shellcheck, manifests, template tests, harness)
bash scripts/verify.sh --fast   # fast gates only (shellcheck)
```

Edit the gates in that script, never here — this doc points, the script
defines.

## Security Checklist

- [ ] No secrets, tokens, or real hostnames in templates, examples, or test fixtures — this repo ships its contents into other people's repos
- [ ] New or changed guard hooks keep failing **open** (a broken guard must never block work) and deny with exit 2 only
- [ ] `SECRET_PATTERNS` changes are mirrored in `hooks/test-guard-secrets.sh` cases and the provider deny-list templates

## Enforcement

```bash
bash scripts/check-harness.sh          # Harness coherence: stub sync, doc links, hook tests, manifest integrity
bash scripts/sync-agent-skills.sh      # Regenerate provider skill stubs from docs/skills/
```
