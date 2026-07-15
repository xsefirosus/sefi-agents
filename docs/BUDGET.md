# BUDGET

How spend is bounded, and the token-discipline stack in the order the levers actually pay
off.

## Enforcement
- `config/budget.yml` declares the caps: per-run, daily, per-dispatch, max-retries,
  max-parallel-worktrees, and per-agent return tokens. `validate-budget.sh` fails if any is
  missing or unbounded.
- `scripts/budget-check.sh` reads those caps and exits nonzero when one is exceeded. The
  retry count comes from the loop's `state/*.md` cycle counter and is never reset on resume.
- Passing a per-dispatch check alone is not sufficient: a dispatch within `per_dispatch_usd_cap`
  can still push cumulative spend over `daily_usd_cap`. Before dispatching, check
  `--scope daily --pending <estimated-cost-of-this-dispatch>` (not just `--scope dispatch`)
  so the estimate is projected against the daily cap before it's actually spent, not
  discovered after.
- Real-spend upgrade (optional): when `ccusage` is on PATH, `budget-check.sh` and
  `/sefi:status` read each agent CLI's own local ledger offline (`--offline`, no network
  mid-loop; `--by-agent` for per-adapter spend). ccusage is never required -- the
  `--spent` fallback keeps the zero-dependency install intact.

## The token-discipline stack (lever order -- biggest first)
1. Code and scope minimization -- the software-engineer climbs the minimization ladder and
   builds less. This is the biggest lever; everything below is smaller.
2. Subagent digests -- research burns tokens in a subagent's window; only a bounded digest
   returns.
3. Progressive disclosure -- skills load name + description until invoked; deep material
   lives in `references/` read on demand.
4. Router-based memory reads -- frontmatter scan, then index, then at most 2 notes; never
   bulk-load.
5. Output compression -- gate/test output is failure-focused and tee'd to a log, not parked
   in context.
6. Terse-mode -- config-gated and last: it compresses phrasing only and nets negative on
   short replies.

## Optional connector note
If you add the codegraph connector (see `OPTIONAL-TOOLS.md`), cite its defensible metric:
~58% fewer tool calls, with file reads dropping to roughly zero across repo sizes. Treat any
blanket token-percentage as noisy and scale-dependent.

## Optional: per-loop-cycle and per-agent budgets (advanced)
For deployments running many simultaneous loops (e.g., one per major project), consider
adding finer-grained caps alongside the per-run and daily limits above:
- **per-loop-cycle:** budget for one complete loop iteration (discovery -> handoff ->
  verification -> persistence), independent of per-dispatch. Use when: multiple loops
  might run in parallel and you want each cycle isolated from the daily budget.
- **per-agent-dispatch:** budget for a single agent's dispatch (not the
  `per_dispatch_usd_cap`, which is per subagent call). Use when: you want to cap
  individual agent costs tighter than the per-run cap.

Implementation: extend `config/budget.yml` with optional `per_loop_cycle_usd_cap` and
`per_agent_dispatch_usd_cap` fields, checked by `budget-check.sh` before dispatching.
Both default to UNKNOWN if not set; the per_run and daily caps remain the hard floor.
Not recommended for v1 -- include only if you have measured evidence a finer-grained
cap is needed.

## Why these specific guards exist (one-line predecessor evidence each)
See `docs/METRICS-PROVENANCE.md` for which of these numbers are predecessor-cited vs.
first-party, and what would promote each one.
- Per-dispatch cap: a single self-batching dispatch hit **1.36M tokens** before any daily cap
  would have noticed.
- Code-enforced batching (<= 3 children per call): prompt-instructed batching was ignored,
  which is how that 1.36M-token run happened and re-ran completed tasks.
- The parse ladder: three calls burned **~324K tokens** on JSON that was present the whole
  time, just not at position 0.
- Tool verification before granting: a broken `browser` tool burned an entire **50-iteration**
  budget retrying the identical failing call.
- The whole stack is load-bearing on a free model: the predecessor's free-model dispatch ran **~45%**
  success; the gates and human checkpoints are what made it viable.
