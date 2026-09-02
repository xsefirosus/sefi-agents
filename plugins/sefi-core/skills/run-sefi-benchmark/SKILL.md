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

Trials run through the out-of-process runner, `benchmarks/runner/run.py` (`git` CLI +
Python 3.11 standard library only). From the repository root, `python3` first then
`python` where `python3` is absent or a non-working Microsoft Store stub:

```sh
python benchmarks/runner/run.py \
  --cases <ids> --strategies control,sefi-chain-sequential \
  --harness <name> --out benchmarks/results/<date>-<slug> [--trials N]
```

- **Each trial is a real `git clone` sandbox**, cut from a fixed full commit id -- never a
  moving branch tip, **never a `git worktree`**. `benchmarks/runner/sandbox.py` clones
  with `--no-checkout --no-hardlinks --no-local` so the clone has its OWN object store,
  writes `.gitattributes` `* -text` and checks out with `core.eol=lf` for a reproducible
  manifest, and tears the scratch dir down in a `finally:`. The clone IS the security
  boundary.
- Each arm gets the case's `prompt_file` verbatim, with its cwd inside the sandbox. The
  case's `allowed_paths` is **enforced**: `benchmarks/runner/snapshot.py` takes an
  out-of-process binary-mode snapshot before and after the arm runs, and any change
  outside `allowed_paths` makes `benchmarks/runner/integrity.py` withhold `integrity_ok`.
- The acceptance check is re-run by the runner from a **PRISTINE copy outside the
  sandbox**: `benchmarks/runner/run.py` resolves `check_<id>.sh` by **absolute path from
  the base checkout** and runs it against the sandbox post-state. An arm-authored
  `acceptance_check` string or `check_<id>.sh` from the trial tree is **never** executed
  -- executing one would run the arm's code in the operator's own shell outside the arm's
  permission constraints (a cross-session privilege-escalation risk, not just a scoring
  risk). From that pristine check the runner records `first_pass_accepted`, allows one
  rework pass for a chain strategy, then re-runs for `accepted`.
- Route evidence is captured **out-of-process**: the runner shells out to check-route.sh
  (the route-evidence shim on `feat/route-evidence-live`) and maps its exit code + one
  JSON stdout line to a single boolean. The arm's own output is never parsed for route
  data. Requested routing is not proof of what ran.
- `benchmarks/runner/record.py` writes every field of every `trials.jsonl` record from
  runner-observed values only; it never copies a field from anything the arm produced.

## Trial integrity -- enforced by benchmarks/runner/

`benchmarks/runner/integrity.verify` is a fail-closed AND of mandatory checks (pre-run
state equals the pinned-ref manifest; no post-run change outside `allowed_paths`; route
evidence captured out-of-process), wrapped in `try/except -> False`. Full detail is in
`benchmarks/README.md` "Trial integrity -- enforced by benchmarks/runner/".

- **Never hand-set `integrity_ok`.** Only `benchmarks/runner/integrity.verify` sets it,
  and only to `true`. A trial it cannot verify omits the key.
- `scorecard.py` is fail-closed: it scores ONLY trials with `integrity_ok` exactly
  `true`; an absent or non-true value is excluded from every delta and from the route
  table. Until check-route.sh is merged onto this branch (or the branch is rebased onto
  `feat/route-evidence-live`), route capture fails closed and a real run scores zero
  trials -- that is intended, not a bug. An unverified score is worse than no score.
- If a trial is known-bad (an arm visibly tampered, or a defect is found later), retain
  it with an `INVALID.md`; never delete it, never silently re-run it.

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
- has a test, `benchmarks/test_scorecard.py`: a fast offline stdlib unit test of the
  SCORER only -- zero model calls, **NOT** a benchmark run. It runs under both
  `python -m pytest` and `python -m unittest`. It and `benchmarks/test_runner.py` (the
  runner-package test) are the two benchmark files `gate.sh` executes. A real benchmark
  run is never triggered by CI, the gate, or a loop -- that is literally true, not just
  intent.
- is **deterministic**: same `trials.jsonl` gives byte-identical output.
- scores ONLY trials with `integrity_ok: true`. It prints
  `scored trials (integrity_ok is true): N` and `excluded (integrity_ok not true): N`
  (missing or non-true is EXCLUDED, never counted clean). Only
  `benchmarks/runner/integrity.verify` sets `integrity_ok`; a hand-authored run omits it
  and scores zero -- see "Trial integrity -- enforced by benchmarks/runner/" above.
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
| "Set `integrity_ok: true` so the scorecard has data." | Only `benchmarks/runner/integrity.verify` may set it; a hand-authored or route-unverified run scores zero trials by design. |
