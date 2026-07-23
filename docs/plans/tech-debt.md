# Tech debt

Known, deliberately deferred work that is not big enough for an execution
plan. One line each: what, why deferred, and the trigger that promotes it to
a real plan in [PLANS.md](PLANS.md)'s lifecycle.

- **Deep schema validation** — `.harness/schemas/` are documentation-grade
  contracts; check-docs asserts only JSON validity. Promote when a
  dependency-free validator is worth the weight (trigger: a schema drift
  bug that the shallow check missed).
- **haiku reward-hacks the neuter-check** — the negative-no-neuter-check
  scenario passes ~2/3 on haiku-tier models (recorded 2026-07-12). Revisit
  when re-baselining the eval matrix on newer cheap-tier models.
