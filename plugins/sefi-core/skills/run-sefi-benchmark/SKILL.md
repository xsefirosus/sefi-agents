---
name: run-sefi-benchmark
description: Operate this repository's real-token-spend blinded paired A/B benchmark -- the full sefi-agents chain versus one strong model on frozen cases, needing explicit per-invocation human authorization of its dollar spend before any model call. Use only when a human explicitly asks to run the sefi benchmark, never for routine retro or efficiency review, and never from a loop.
managed-by: sefi-agents
---

# Run Sefi Benchmark

Operate the blinded paired A/B harness that compares the full sefi-agents chain against
one strong model on a frozen set of cases. The design of record and the trial-record
schema live in `benchmarks/README.md`; this skill is the run-and-report workflow.

User instructions always override this skill.
All factual output follows the anti-hallucination skill: cite or mark UNKNOWN, never
guess. Missing telemetry is `null`, never `0`.

## Cadence -- never inside a loop

Run this per release, or monthly, or when a human explicitly asks. It is manual and
out-of-loop by construction. **Never more than one benchmark run per day, AND only with
explicit per-invocation authorization** -- there is no standing pre-authorization, a day
passing does not auto-approve a run, and a prior approval never carries to the next run.
Same statement in `docs/BUDGET.md` and `docs/METRICS-PROVENANCE.md`. A `loops/*.loop.md`
spec MUST NOT call this skill: a benchmark run spends real tokens and time well past
`per_run_usd_cap`, and an unattended loop has no authority to approve that. If a loop
needs benchmark evidence, it parks a request in `inbox/` for a human.

Nothing mechanically prevents a loop from invoking this skill -- there is no runtime
guard that blocks a `loops/*.loop.md` from naming it. The "no loop may call this" rule is
model-compliance prose, backed by the explicit-per-invocation-authorization gate below
(step 2), which a compliant operator will not clear for an unattended loop. Narrowing the
`description` above so it does not auto-trigger on routine retro/efficiency phrasing is
the other half of that mitigation.

## The two arms

Both arms run against the **same frozen case packet** and the **same acceptance checks**,
paired on `case_id` + `trial`:

- **control** -- one `high`-tier model alone in an isolated git worktree.
- **treatment** -- the full sefi-agents chain in its own isolated git worktree.

Label the treatment arm by how dispatch actually ran:

- `strategy: sefi-chain` -- real parallel subagent dispatch.
- `strategy: sefi-chain-sequential` -- the roster ran sequentially in one context (a
  harness with no subagent tool, or Codex without `multi_agent = true`).

Never equate the two labels. See the harness matrix in `benchmarks/README.md`: Claude
Code first, Codex second; OpenCode and Hermes are deferred because their tiers resolve to
the `flexible` sentinel and the control arm then has no fixed model identity.

## Before any model call

1. Produce a **dry-run plan**: the exact trial matrix (cases x arms x harnesses x
   repetitions), the base commit each worktree is cut from, and the target output
   directory. Producing the plan makes **zero model calls**.
2. Get **explicit per-invocation authorization** of the token and time spend for that
   specific matrix. A benchmark run is exempt from `per_run_usd_cap` / `daily_usd_cap`
   (`docs/BUDGET.md`) only by being manual and separately ceiling-ed -- it is not covered
   by `${CLAUDE_PLUGIN_ROOT}/scripts/budget-check.sh`. No authorization, no run.
3. Never silently widen the matrix, add repetitions, or retry a costly failed run.

## Running a trial

- **One isolated git worktree per trial**, cut from a fixed full commit id -- never a
  moving branch tip. The control and treatment arms get separate worktrees. This worktree
  is for isolating concurrent trials; **it is NOT a security boundary** -- a git worktree
  shares `.git` (including `.git/info/exclude`) with its base, so an arm can reach what the
  base sees. See `benchmarks/README.md` "Trial integrity -- NOT IMPLEMENTED in this
  version".
- Hand each arm the case's `prompt_file` verbatim. The case's `allowed_paths` /
  `immutable_paths` describe what the trial is meant to touch; in this version they are
  advisory and nothing enforces them.
- Run each case's `acceptance_check` from a **pristine copy outside the trial worktree**:
  resolve both `check_<id>.sh` and the `acceptance_check` command string from the base
  checkout -- or from a fresh copy of `benchmarks/cases/` and `cases.json` the arm never
  had write access to -- and invoke it **by absolute path** against the arm's output tree,
  **never from the trial worktree**. Because `immutable_paths` is advisory and nothing
  enforces it, an arm can rewrite BOTH its `acceptance_check` string in `cases.json` AND
  its own `check_<id>.sh` in its worktree; executing an arm-authored `acceptance_check`
  string or `check_<id>.sh` then runs the arm's code in the operator's own shell, outside
  whatever permission constraints applied to the arm -- a cross-session
  privilege-escalation risk, not just a scoring risk. This is the same rule as "never copy
  a field from anything the arm produced" below: an executed check is such a field.
- Using that pristine check, record `first_pass_accepted`, allow one rework pass if the
  chain's own review calls for it, then re-run for `accepted`.
- Record observed route evidence per lane (model, effort, expected_effort, and
  expected_model when known). Requested routing is not proof of what ran.
- Append one JSON object per trial to `trials.jsonl` in the output directory, per the
  schema in `benchmarks/README.md`. The operator writes every record from OUTSIDE the
  trial worktree; never copy a field from anything the arm produced.

## Trial integrity -- NOT IMPLEMENTED in this version

Nothing in this version verifies that an arm did not edit its own acceptance check,
rewrite the answer key, or change files outside `allowed_paths`. There is no filesystem
sandbox and no out-of-process diff. Full detail and the requirements for a future
sandboxed runner are in `benchmarks/README.md` "Trial integrity -- NOT IMPLEMENTED in
this version".

- **Do NOT record `integrity_ok: true`** from anything available in this version -- there
  is no component entitled to set it. Leave the field ABSENT on every real-run record.
- `scorecard.py` is fail-closed: it scores ONLY trials with `integrity_ok` exactly
  `true`; an absent or non-true value is excluded from every delta and from the route
  table. So a real run scores zero trials until a sandboxed runner exists -- that is the
  intended behaviour, not a bug. An unverified score is worse than no score.
- If a trial is known-bad (an arm visibly tampered, or a defect is found later), retain
  it with an `INVALID.md` and record `integrity_ok: false`; never delete it, never
  silently re-run it.

## The blinded judge

- Optional quality score only. The objective acceptance checks are always authoritative.
- The judge runs **read-only** in a **fresh context separate from both arms**. It never
  sees which arm produced an artifact.
- Judge tokens and judge wall time are recorded **separately** from either arm's totals,
  never folded in.
- If the judge cannot be reached, record `quality_score` as absent / `null`. Do not
  substitute a number.

## Output directory

- Choose a **new, empty** output directory for every run
  (`benchmarks/results/<date>-<slug>/`). `benchmarks/results/` is git-ignored -- raw
  artifacts are never committed.
- **Refuse a non-empty output directory.** Evidence from separate runs must never be
  mixed in one directory.
- On promotion (see `docs/METRICS-PROVENANCE.md`), copy ONLY the `scorecard.py` output out
  of the run dir, committed as `benchmarks/published/<date>-<slug>.scorecard.txt`.
- Do not change global harness configuration, push, publish, or touch production systems.

## Invalid runs

If a run's reviewer verdict is REJECT, or a design defect is found afterward:

- Keep the raw artifacts on disk. Write an `INVALID.md` at the run directory root stating
  why the run must not be used.
- Never delete the run. Never silently re-run it.
- Never auto-launch a replacement benchmark -- return control to the human.

## Scoring

`python3 benchmarks/scorecard.py <output-dir>/trials.jsonl` (use `python` where `python3`
is absent or a non-working stub). The scorer:

- is **Python 3 standard library only**, dev-only contributor tooling. It makes no model
  call, no dispatch, no network request, and writes nothing. It is **never** wired into
  `run-all.sh`, a CI job, a loop, or a dispatched-agent path.
- has one test, `benchmarks/test_scorecard.py`: a fast offline stdlib unit test of the
  SCORER only -- zero model calls, **NOT** a benchmark run. It runs under both
  `python -m pytest` and `python -m unittest` and is the only benchmark file `gate.sh`
  executes. A real benchmark run is never triggered by CI, the gate, or a loop -- that is
  now literally true, not just intent.
- is **deterministic**: same `trials.jsonl` gives byte-identical output.
- scores ONLY trials with `integrity_ok: true`. It prints
  `scored trials (integrity_ok is true): N` and `excluded (integrity_ok not true): N`
  (missing or non-true is EXCLUDED, never counted clean). Nothing in this version sets
  `integrity_ok`, so a real run's records omit it and score zero trials -- see "Trial
  integrity -- NOT IMPLEMENTED in this version" above.
- prints a run-cost line against the `benchmark_per_run_usd_cap` ceiling in
  `config/budget.yml` -- `run cost $X.XX vs ceiling $15.00 [config/budget.yml]:
  WITHIN / OVER` when every scored trial carries `cost_usd`, `run cost: unknown (...)`
  when one does not, and `run cost: ceiling unreadable (...)` (never `WITHIN`) if that
  key is non-finite / non-positive / unparseable.
- prints an **aggregate-delta block** (per case and overall, `sefi-chain` and
  `sefi-chain-sequential` each versus `control`, kept distinct) and a **separate
  route-correctness block** (observed vs expected model/effort per lane), the latter built
  from the scored trials only.
- Full paired-bootstrap confidence intervals are deferred; it ships point deltas plus the
  route axis.

## Reporting

- Report objective acceptance before any judge score.
- Cite **both axes**: the delta block for "was the outcome better", the route-correctness
  block for "did the right model run". An outcome win with a route-incorrect lane is not
  a clean win.
- A result showing the chain **losing** on some task classes is an accepted outcome, not
  a harness failure. Report it plainly.
- Benchmark numbers are cited from `docs/METRICS-PROVENANCE.md`, which records that the
  harness is out-of-loop and its spend is separately authorized.
- Keep every missing measure as `null` / `n/a`. A small local case set is directional
  local evidence, not a product-wide claim.

## Common Rationalizations

| Excuse | Rebuttal |
|---|---|
| "Just wire the scorer into CI for coverage." | It is dev-only stdlib tooling; it never runs in CI, a loop, or a dispatched path. |
| "The chain lost, the harness must be broken." | A chain loss on a task class is a valid, publishable result. |
| "Re-use the last output directory." | Refuse a non-empty output dir; mixed-run evidence is void. |
| "The judge timed out, score it 0." | Missing telemetry is `null`, never `0`. |
| "A loop can run this monthly on its own." | No `loops/*.loop.md` may call this; a run needs explicit human spend authorization. |
| "Set `integrity_ok: true` so the scorecard has data." | Nothing in this version may set it; a real run scores zero trials by design until a sandboxed runner exists. |
