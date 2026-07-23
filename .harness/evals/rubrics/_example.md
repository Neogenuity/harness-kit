# Rubric: <slug> (semantic / LLM-as-judge)

Use a rubric **only** when the acceptance criterion is genuinely semantic —
"reads clearly", "explains the why", "follows the house voice" — and no
executable `check.sh` can decide it. Executable checks are the default; they
need no calibration. A rubric is **advisory**: it never blocks a gate.

## Criteria

Score each on a fixed scale (e.g. 1–5) and define what each point means, so two
judges (human or model) reach the same verdict:

- **<dimension 1>** — <what a 5 looks like vs a 1>
- **<dimension 2>** — <…>

Pass threshold: <e.g. every dimension ≥ 4>.

## Judge

- Model: `<the judged model, pinned>`
- Prompt: `<path to the judge prompt, or inline>`
- Input: the trial transcript under `.harness/var/eval-results/<task>/<run>/trial-N/`.

## Calibration

An LLM-as-judge is only trustworthy once a human has confirmed it agrees with
human judgement on a sample. Record that here and re-run it whenever the rubric
or the judged model changes.

<!-- Fill in after each calibration pass: -->
- **YYYY-MM-DD** — <name> read <N> transcripts and compared them to this rubric's
  verdicts: <M>/<N> agreed. Disagreements: <what and why>. Action: <none |
  tightened criterion X | switched judge model>. Judged model: `<model>`.

Until a dated line above exists, treat this rubric's scores as unvalidated and
do not report them as results.
