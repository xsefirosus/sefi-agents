# Loop: morning-triage
managed-by: sefi-agents

agentic-signals: goal_intake, refusal_gate, verification, loop_discipline, close_out

## Trigger (SCHEDULING)
cloud: cron `0 6 * * *` via `.github/workflows/triage.yml`   |   local: daily 06:00 interval invoking the headless agent

## Discovery
skill: loop-engineering (discovery move)   inputs read: failed CI, issues in the last 24h, commits since the last run, and the prior `state/triage.md`. Judge each finding's actionability; drop the noise.

## Handoff
one worktree per kept finding: branch `triage/<slug>` under `.worktrees/`   max parallel: 3 (from `config/budget.yml` max_parallel_worktrees). Each dispatched task names its absolute worktree output path.

## Verification
generator: implementer   evaluator: evaluator (different model where possible)
stop condition: the plan's numbered-checkbox list is fully checked AND the evaluator PASSes against the plan's `## Done Criteria` (executed, judged separately from the generator).

## Persistence
state file: `state/triage.md` (committed, carries the 5-field resume block; one row per finding)
metrics: append one row per evaluator verdict to `state/metrics.md` (target-path keyed)
outputs: PRs + `inbox/` for uncertainty

## Budget (from config/budget.yml)
per-run cap: $0.50   daily cap: $2.00   max retries: 2

## Human checkpoint
PRs are opened, never merged. Anything below the evaluator's confidence bar goes to `inbox/`.
See `skills/sefi-orchestration/references/human-checkpoint.md` for the full rule and why.
