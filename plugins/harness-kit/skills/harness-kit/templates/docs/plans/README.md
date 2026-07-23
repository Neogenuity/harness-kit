# Execution Plans

Long-horizon work needs state that survives context windows: what is being
built, how far it got, what was decided, and what "done" means.
`scripts/harness/hooks/session-context.sh` announces every plan in `active/` at session
start (the directory is set by `PLANS_DIR` in `scripts/harness/harness.conf`), so a
fresh session — or a subagent in a worktree — starts oriented instead of
re-deriving context.

In-repo plans with progress and decision logs are converged cross-vendor
practice: compaction alone is insufficient for long-running agents; persistent
progress artifacts and structured handoffs are what let a resuming session
continue from the file alone.

## Lifecycle

- `docs/plans/*.md` — **queued**: scoped and prioritized, not started.
- `docs/plans/active/` — **in execution**: announced every session start. Keep
  this to the one or two plans actually being worked.
- `docs/plans/completed/` — **shipped**: moved here (create the directory on
  first use) once the work lands and Verification is filled in with real
  evidence.

Move plans between states with `git mv` — never copy.

**Naming.** The active plan carries its release/milestone identifier (its scope
pins that milestone). Queued plans are named by **theme**, not a number —
milestones are assigned only when a plan moves to `active/`, because what
actually ships (and interstitial releases) shift the numbering. A roadmap
shouldn't promise numbers it can't keep.

## Plan format

Every plan carries these sections; a resuming session must be able to continue
from the file alone:

| Section | Answers |
| --- | --- |
| Objective | The outcome, in one paragraph |
| Value | Why this, why now, why in this order |
| Scope | Deliverables as a checklist, each with an acceptance criterion |
| Out of scope | What is deliberately deferred, so it isn't relitigated |
| Dependencies | What must exist or merge first |
| Verification | The evidence that will prove completion (commands, evals) |
| Progress | Dated running log, newest first |
| Decisions | Dated choices and their why |
| Next action | The single next step a resuming session takes |

Start a new plan by copying [`_template.md`](_template.md).

## Honesty rule (why some paths are links and some are not)

`check-harness.sh` link-checks every markdown link under `docs/` and fails the
build on a dead one. So: repo references that must **stay honest** — a doc that
exists, a real file the plan touches — belong in **markdown links**, and CI
guarantees they resolve. Prose and `backtick` mentions of **not-yet-existing**
paths are deliberately left alone: a queued plan naming a file it will create
is honest roadmapping, not a broken link. Write future paths in backticks;
promote them to links once they exist.

## Roadmap

<!-- The ordered queue to the next milestone. Link each plan; keep the ordering
     rationale short. Re-sorting is expected — every harness component encodes
     an assumption about what a model can't do alone, and those assumptions get
     stress-tested on each model/provider shift. Example shape:

Shipped: **vX.Y** — <one line> ([completed/vX.Y-<theme>.md](completed/vX.Y-<theme>.md)).

| # | Plan | Theme |
| --- | --- | --- |
| 1 | [<theme>.md](<theme>.md) | <one-line theme> (next up) |
-->
