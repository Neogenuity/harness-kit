# Skill-split parity — monolith vs router (v0.13.0)

Fresh paired evidence for the [skill-split plan](../../plans/completed/v0.13.0-skill-split.md):
does splitting the plugin `SKILL.md` into a compact router +
`references/modes/{init,audit,add,update}.md` regress correctness or wall-clock
versus the monolith? **Recorded 2026-07-13.**

## Gate (from the plan)

Ship the split only if **all three** hold:

1. Router activation ≤ 1k tokens.
2. Split correctness ≥ monolith on every paired task.
3. Wall-clock no worse (per-task median; a timeout counts as the configured
   timeout, never a dropped trial).

## Configuration

- **Monolith arm `C`** — the current `SKILL.md` (299 lines, ~5.2k tokens),
  cloned from committed `HEAD` `5f1e4ec` and loaded via `--plugin-dir`.
- **Split arm `CR`** — the candidate router (81 lines, **586 words ≈ 781
  tokens**) + `references/modes/`, staged into the audit harness's
  `reduced-plugin/harness-kit`.
- Harness: `.harness/context-efficiency-eval/scripts/run-cell2.sh`, back-to-back
  in one environment. Model **claude `sonnet`** (within-tier, same model both
  arms — a true monolith-vs-split comparison). **3 trials/cell**, 600s timeout.
- Tasks: the two adopted discriminating tasks, `hn-add-skill` and
  `tmpl-secret-pattern`.
- **Scope note (focused):** run on claude `sonnet` only. The cross-tier
  haiku↔terra cells from the July audit were **not** reused (stale, and the
  plan warns against them); this is a same-model monolith-vs-split delta, which
  is the correctness question the gate asks.

## Results

| task | arm | pass_rate | med_wall_s | med_total_tokens | tokens/success | cost/success |
| --- | --- | --- | --- | --- | --- | --- |
| hn-add-skill | `C` monolith | **3/3** | 269 | 1,074,493 | 1,044,050 | $0.6169 |
| hn-add-skill | `CR` **split** | **3/3** | **256** | 1,017,902 | **786,785** | $0.6167 |
| tmpl-secret-pattern | `C` monolith | **3/3** | 600 | 4,286,542 | 4,040,623 | $0.6645 |
| tmpl-secret-pattern | `CR` **split** | **3/3** | 600 | 3,792,615 | **3,544,410** | **$0.3598** |

Per-trial (`driver.log`): every trial scored PASS on both arms. Two
`tmpl-secret-pattern` trials per arm hit the 600s watchdog (`rc=124`) yet still
reached the correct graded end-state — the agent finished the work but did not
self-terminate; the cap counts as 600s in `med_wall_s` for both arms, so the
comparison stays fair.

## Verdict — PASS → ship

1. Router activation **781 tokens ≤ 1k** ✓ (monolith was ~5.2k — an ~85%
   activation-footprint cut).
2. Correctness **3/3 = 3/3** on both tasks — split ≥ monolith ✓.
3. Wall-clock: hn-add-skill split **256 ≤ 269**; tmpl-secret-pattern **600 =
   600** — no worse ✓.

Bonus (not required by the gate): the split is *cheaper* — 25% fewer
tokens/success on hn-add-skill, and 46% lower cost/success on
tmpl-secret-pattern — consistent with the audit's ~4.2k-tokens/activation
prediction compounding over multi-turn tasks.

The split ships in v0.13.0. Raw per-trial metrics:
`.harness/context-efficiency-eval/results/parity-v0.13.0/` (git-ignored).
