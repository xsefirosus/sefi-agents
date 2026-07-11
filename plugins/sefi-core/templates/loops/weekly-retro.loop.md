# Loop: weekly-retro
managed-by: sefi-agents

agentic-signals: goal_intake, refusal_gate, verification, loop_discipline, close_out

## Trigger (SCHEDULING)
cloud: cron `0 7 * * 1` (Mondays) via a workflow file   |   local: weekly interval invoking the headless agent

## Discovery
skill: retro-improve (discovery move)   inputs read: evaluator REJECTs, gate failures, and librarian `## Possible contradiction` flags from `state/`, plus `state/metrics.md` (worst success rate first).

## Handoff
one worktree per improvement target: branch `retro/<slug>` under `.worktrees/`   max parallel: 1 (self-improvement is single-writer). Each dispatched task names its absolute worktree output path.

## Verification
generator: retro-improve (proposes bounded edits)   evaluator: evaluator (different model where possible)
stop condition: the proposed edit is <= 3 sentences per file AND lands in a `managed-by: sefi-agents` file the runtime loads; otherwise it becomes an `inbox/` proposal, judged separately from the generator.

## Persistence
state file: `state/retro-<date>.md` (committed; carries the 5-field resume block and the SKIP reason when nothing changed)
metrics: read `state/metrics.md` as the scorecard; append the retro outcome row
outputs: applied skill edits if `improvement.enabled: true`, else a proposal in `state/retro-<date>.md`; new skills go to `inbox/`

## Budget (from config/budget.yml)
per-run cap: $0.50   daily cap: $2.00   max retries: 2

## Human checkpoint
New skills require inbox approval; no skill is created autonomously, and no host-runtime file is edited.
See `skills/sefi-orchestration/references/human-checkpoint.md` for the full rule and why.
