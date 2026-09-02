# METRICS PROVENANCE

Every number cited in this repo's docs is either first-party (measured from this exact
system's own runtime) or predecessor-cited (observed in the prior Python/FastAPI build,
honestly labeled as such). This ledger tracks which is which, and what would need to be
true to promote a predecessor-cited row to first-party. Never invent a first-party number
to fill a row early -- an unmet promotion condition stays predecessor-cited, per this
repo's own anti-hallucination convention.

| Claim | Current source | Where cited | Promotion condition |
|---|---|---|---|
| Free-model dispatch success ~45% | Predecessor | `docs/BUDGET.md` | 4+ weeks of `state/metrics.md` PASS-rate rows from a live free-model loop on this architecture |
| Single dispatch hit 1.36M tokens (self-batching) | Predecessor | `docs/BUDGET.md` | A measured per-dispatch token total from `state/metrics.md` on this system, run with the per-dispatch cap already in place (expected to never reproduce the incident, which is itself the evidence the cap works) |
| Parse-ladder rescue avoided ~324K tokens (JSON present, not at position 0) | Predecessor | `docs/BUDGET.md` | A logged instance where this system's parse ladder actually recovered a reply the first rung missed, with the token cost of the naive re-ask it avoided |
| Broken browser tool burned a 50-iteration retry budget | Predecessor | `docs/BUDGET.md` | A logged instance where `probe-tools.sh` actually caught a BROKEN or MISSING tool before a loop retried against it. Note: until v0.2.3 this condition named a mechanism that did not exist, so it was unreachable rather than merely unmet; the probe now ships, and the condition is live |
| 184 green tests, half the new modules unwired | Predecessor | `docs/ANTIPATTERNS.md` | A qa-engineer wired/delete-the-line finding on this system's own code, with a before/after count of tests vs. actually-reachable modules |
| 5 config keys declared but never read or named as a rule; 0 after fix | First-party | `README.md`, `CHANGELOG.md` [0.2.1] | N/A -- already first-party, verified live by `validate-config-wired.sh`, a permanent CI gate |
| 6 shipped files referenced paths that resolved to nothing; 0 after fix | First-party | `README.md`, `CHANGELOG.md` [0.2.1] | N/A -- already first-party, verified live by `validate-links.sh`, a permanent CI gate |
| Budget-enforcement gate silently passed with no spend data (confirmed live: no `ccusage`/`jq` on the build machine) | First-party | `README.md`, `CHANGELOG.md` [0.2.1] | N/A -- already first-party, proven by an executed regression test in `test-scripts.sh`, not just read |
| Every OpenCode subagent dispatch failed with `Model not found: sonnet/`, live-observed on a real user install (not internal testing) | First-party | `adapters/OPENCODE.md`, `CHANGELOG.md` [0.2.2] | N/A -- already first-party, verified by re-running `install-opencode.sh` against every one of the 13 agents and confirming `model:` is absent; proven by an executed regression test in `test-scripts.sh` |
| `budget-check.sh` failed open a second time -- `ccusage` present but returning `null`/empty/crashing was coerced to `0` spend | First-party | `README.md`, `CHANGELOG.md` [0.2.3] | N/A -- already first-party, proven by executed regression tests that stub each unusable `ccusage` shape onto PATH |
| `gate.sh` enforced no timeout, while `loop-engineering` shipped the per-operation-timeout-class rule | First-party | `README.md`, `CHANGELOG.md` [0.2.3] | N/A -- already first-party, proven by an executed test that hangs a suite against a 2s class budget and asserts the kill |
| A failing command could produce zero diagnostics when its output named no error keyword | First-party | `CHANGELOG.md` [0.2.3] | N/A -- already first-party, proven by an executed test asserting the output tail appears |
| The SessionStart injection spent roughly half its 1500-char budget on static preamble (the router block starts at line 21 of the shipped index template) | First-party | `README.md`, `CHANGELOG.md` [0.2.3] | N/A -- already first-party, proven by an executed test asserting the preamble is absent and router lines present |
| The five-move loop gate was satisfiable by prose (`grep -q Discovery` matched the word anywhere) | First-party | `README.md`, `CHANGELOG.md` [0.2.3] | N/A -- already first-party, proven by an executed test scoring a prose-only spec at 40/100 |
| The README claimed a tool probe that existed nowhere in the repo | First-party | `README.md`, `CHANGELOG.md` [0.2.3] | N/A -- already first-party; the mechanism now ships and the claim was rewritten to match it |
| The memory vault had a consumer and no producer -- `memory/daily/` was read weekly and written by nothing | First-party | `README.md`, `CHANGELOG.md` [0.2.3] | N/A -- already first-party, proven by an executed test asserting an agent authors daily notes and each loop dispatches close_out |

The first three rows above are this ledger's first first-party rows, and arrived by a
different path than the "Standing check" below: a direct audit found and fixed them
same-day, not a `weekly-retro` cycle accumulating `state/metrics.md` evidence over time.
The distinction still holds -- each was measured on this system's own runtime, not
inherited from the predecessor.

The fourth row is a different provenance again: this ledger's first finding sourced from
actual field usage rather than internal audit or testing -- a real user hit it running
sefi-agents on OpenCode, not a controlled check. Worth naming as its own category: a live
user report is stronger provenance than an internal test, not weaker, precisely because
nothing about the failure was staged.

The seven rows after it come from the 2026-08-11 full-repo audit and share a shape worth
naming: each is a mechanism this repo had already DOCUMENTED and not implemented, or
implemented and left reachable by prose. Two of them (`budget-check.sh` failing open, the
loop gate satisfiable by prose) are second occurrences of a bug class this repo had already
fixed once elsewhere -- evidence that a fix applied to one branch of a check does not
generalise itself, and that the validator asserting a rule is not the same artifact as the
rule. That is the argument for every one of them landing as an executed regression test
rather than a corrected sentence.

## Benchmark evidence (blinded paired A/B harness)

Any number this repo cites about the sefi-agents chain versus a single strong model comes
from a recorded run of the harness in `benchmarks/` (design of record:
`benchmarks/README.md`; workflow: `plugins/sefi-core/skills/run-sefi-benchmark/SKILL.md`),
cited from here with the run directory named. Rules for that evidence:

- The harness is **out-of-loop**. It is manual, human-authorized per invocation, and its
  spend is **not** covered by `budget-check.sh` and is outside every scope it checks. It
  has an operator-tracked per-run target of USD 15.00 (`benchmark_per_run_usd_cap` in
  `config/budget.yml`, `docs/BUDGET.md`) that is **not enforced** -- `scorecard.py` prints
  `run cost $X.XX vs ceiling $15.00: WITHIN / OVER` (or `run cost: unknown ...` when a
  scored trial lacks `cost_usd`) from the summed trial `cost_usd`, with no automated
  block. No `loops/*.loop.md` may trigger it.
- Cadence: **never more than one run per day, AND only with explicit per-invocation
  authorization** -- no standing pre-authorization, no automatic daily run. Same statement
  in `docs/BUDGET.md` and `plugins/sefi-core/skills/run-sefi-benchmark/SKILL.md`.
- A run reports two independent axes: outcome deltas (paired treatment-minus-control) and
  a **separate route-correctness table**. Cite both. An outcome win on a trial whose lane
  ran the wrong model is not a clean win.
- Missing telemetry is `null`, never `0`. A `null` in a scorecard is absent data.
- A result showing the chain **LOSING** on some task classes -- slower, more tokens, no
  better acceptance -- is an accepted, citable outcome about where the chain does not pay
  for itself. It is not a harness failure and is not re-run away.
- A run whose reviewer verdict is REJECT is retained with an `INVALID.md` and is never
  cited as evidence (see `state/retro-ledger.md`).
- **The raw run directory `benchmarks/results/<date>-<slug>/` is git-ignored and never
  committed.** Promotion copies ONE artifact out of it: the `scorecard.py` output, checked
  in as `benchmarks/published/<date>-<slug>.scorecard.txt` (that directory is tracked).
  The citation names both the published scorecard and the local run slug.
- Until a published scorecard exists under `benchmarks/published/`, this repo has **no
  first-party chain-versus-control numbers**; the row below stays UNKNOWN rather than
  being filled from the predecessor or an estimate.
- **Out-of-process trust boundary.** Trial integrity is enforced by the runner package
  `benchmarks/runner/` (see `benchmarks/README.md` "Trial integrity -- enforced by
  benchmarks/runner/"). The **runner process, not any arm**, writes every field of every
  trial record: `benchmarks/runner/record.py` builds records from runner-observed values
  only and never reads arm stdout. Route evidence comes only from the runner shelling out
  to check-route.sh (an out-of-process helper); no arm-written value is a scoring input.
  Each trial runs in a real `git clone` sandbox with its own object store (never a
  `git worktree`), and an out-of-process binary-mode snapshot + diff flags any change
  outside the case `allowed_paths`. `benchmarks/runner/integrity.verify` is a fail-closed
  AND of those checks (`try/except -> False`); it is the ONLY thing that sets
  `integrity_ok`, and only to `true`. An aborted run (budget pre-flight or running
  ceiling) writes `ABORTED.md` and never produces `trials.jsonl`, so partial data is
  structurally unscoreable. `scorecard.py` then filters to `integrity_ok is True`.
- Positive route capture requires check-route.sh, which lives on
  `feat/route-evidence-live` @ `8c1779c` and is NOT on the `feat/benchmark-runner`
  branch. Until that is merged (or the branch rebased onto it), route capture fails
  closed and every trial is non-scored, so the benchmark number stays UNKNOWN for lack of
  a scoreable run -- not by construction.

| Claim | Current source | Where cited | Promotion condition |
|---|---|---|---|
| sefi-agents chain vs single strong model: outcome + route-correctness deltas | UNKNOWN (no run yet) | (none yet) | A completed run (raw artifacts under the git-ignored `benchmarks/results/<date>-<slug>/`) with >=2 repetitions per case and a non-REJECT reviewer verdict, whose `scorecard.py` output is committed as `benchmarks/published/<date>-<slug>.scorecard.txt` |

## Standing check

During the weekly-retro pass, consult this ledger. If accumulated `state/metrics.md` data
now satisfies a promotion condition, propose the doc update as a normal bounded retro edit
(subject to the qa-engineer's pre-commit effectiveness check). An unmet condition is left
as-is -- this ledger tracks the gap, it does not manufacture evidence to close it early.
