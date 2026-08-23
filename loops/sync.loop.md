# Loop: sync
managed-by: sefi-agents

agentic-signals: goal_intake, refusal_gate, verification, loop_discipline, close_out
requires-tools: git, rg
<!-- probed by scripts/probe-tools.sh --loop before the Discovery move runs. Deliberately
minimal: this loop targets any project's own package manager (npm, pip, cargo, go, ...),
never one hardcoded here, so a manager-specific outdated-check is used opportunistically in
Discovery when present and skipped, not required, when absent. -->

## Trigger (SCHEDULING)
cloud: cron `0 8 * * 1` (Mondays, offset an hour from weekly-retro's 07:00 slot so the two
never contend for the same worktree budget) via a workflow file   |   local: weekly interval
invoking the headless agent

## Discovery
skill: loop-engineering (discovery move)   agent: support-engineer   inputs read: the
project's own manifest/lockfile for outdated or deprecated packages (via whichever
manager's outdated-check the project provides -- `npm outdated`, `pip list --outdated`, or
equivalent; skipped, not failed, when none applies), CI failures attributable to a
dependency, and the prior `state/sync.md`. Judge each finding's actionability:
a patch bump with no CHANGELOG signal ranks below a failing build or a security advisory.

## Handoff
one worktree per upgrade: branch `sync/<slug>` under `.worktrees/`. Once a finding is
planned, `scripts/ready-steps.sh` computes that plan's dispatch set, capped at max
parallel: 3 (`config/budget.yml` max_parallel_worktrees) -- never reasoned about in prose.
Each dispatched task names its absolute worktree output path. Before opening it, grep
other `state/*.md` for a matching `acting_on`; skip and log if already claimed.

## Verification
generator: software-engineer   evaluator: qa-engineer (different model where possible),
one pass per upgrade -- never batched, so one broken bump never blocks the rest
stop condition: the plan's numbered-checkbox list is fully checked AND the qa-engineer
PASSes against the plan's `## Done Criteria` -- the project's own existing test suite
passing against the bumped dependency (executed, judged separately from the generator,
never a CHANGELOG read as if it were a test result).

## Persistence
state file: `state/sync.md` (committed, carries the 6-field resume block; one row
per upgrade)
metrics: append one row per qa-engineer verdict to `state/metrics.md` (target-path keyed)
outputs: PRs + `inbox/` for uncertainty (a major-version or otherwise breaking bump goes to
`inbox/` instead of a direct PR)
close_out: dispatch the knowledge-manager to file this cycle's durable observations to
`memory/daily/` (privacy-filtered, tier: trace), or log SKIP with a reason -- never
neither. Rule: `skills/sefi-orchestration/references/close-out.md`

## Budget (from config/budget.yml)
per-run cap: $0.50   daily cap: $2.00   max retries: 2

## Cost Profile
| Scenario | Est. tokens | Notes |
|---|---|---|
| no-op | UNKNOWN | no run history yet; fill from state/metrics.md after the first week |
| report only | UNKNOWN | |
| full fix attempt | UNKNOWN | |

## Human checkpoint
PRs are opened, never merged. A major-version or breaking-change bump is routed to
`inbox/` instead of a direct PR, same escalation the other two loops use for uncertainty.
See `skills/sefi-orchestration/references/human-checkpoint.md` for the full rule and why.
