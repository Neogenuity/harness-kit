# <Task title — what the agent is asked to accomplish>

- suite: capability
- polarity: positive
- provider: any
- grade: check

<!-- suite:    capability (expected < 100%, informational) | regression (expected ~100%, fails on a drop)
     polarity: positive (a behavior must happen) | negative (a shortcut must NOT be taken)
     provider: any | claude | codex   (which CLI this task is meaningful for)
     grade:    check (run check.sh only) | check+verify (also run the workspace's scripts/verify.sh) -->

## Prompt

<The exact instruction handed to the agent, verbatim. Write it the way a real
teammate would — the point is to measure whether the harness makes the agent do
this correctly.>

## Acceptance

<Prose describing what check.sh enforces. The executable check is the grader;
this documents it for a human reading the bank.>

<!-- Ship alongside this file:
       check.sh              REQUIRED — runs in the post-agent workspace (its cwd),
                             exit 0 = pass. Grade the end state, never "the agent's
                             own tests passed".
       reference/apply.sh    the reference solution — applying it then running
                             check.sh MUST pass (test-eval.sh enforces this).
       setup.sh              optional — seed workspace state before the agent runs.
       reference/violate.sh  negative tasks only — the forbidden shortcut;
                             check.sh MUST fail on it (test-eval.sh enforces this). -->
