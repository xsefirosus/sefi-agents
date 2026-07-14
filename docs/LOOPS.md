# LOOPS

See `docs/LOOP-FAILURE-MODES.md` for the runtime incident catalog (distinct from
`docs/ANTIPATTERNS.md`'s build/authoring mistakes).

A loop discovers work, hands it off, verifies it, persists state, and reschedules itself.
Every loop implements all five moves. This doc is the loop-spec template, the worktree
procedure, the resume block, and the inbox contract.

## Loop-spec format (follow in every `*.loop.md`)
```markdown
# Loop: <name>
managed-by: sefi-agents

## Trigger (SCHEDULING)
cloud: <cron expr + workflow file>   |   local: <interval + invocation>
## Discovery
skill: <skill that finds the work>   inputs read: <CI/issues/commits/state>
## Handoff
one worktree per finding: <branch naming>   max parallel: <from budget.yml>
## Verification
generator: software-engineer   evaluator: qa-engineer (different model where possible)
stop condition: the plan's numbered-checkbox list is fully checked AND the qa-engineer
PASSes against ## Done Criteria (executed, judged separately from the generator)
## Persistence
state file: state/<name>.md (committed, carries the 6-field resume block)
metrics: append one row per qa-engineer verdict to state/metrics.md (target-path keyed)
outputs: PRs + inbox/ for uncertainty
## Budget (from config/budget.yml)
per-run cap: $<x>   daily cap: $<y>   max retries: <n>
## Human checkpoint
<what is never automated -- e.g., "PRs are opened, never merged">
```

Also declare the agentic-signals line so `validate-loops.sh` confirms the loop gates rather
than advises: `agentic-signals: goal_intake, refusal_gate, verification, loop_discipline, close_out`.

## The five moves in repo terms
- Discovery: a skill reads CI / issues / commits / state and judges actionability.
- Handoff: one git worktree per finding (procedure below).
- Verification: the qa-engineer plus an executed stop condition, judged separately from
  the generator.
- Persistence: `state/*.md` committed, carrying the cross-iteration notes bridge.
- Scheduling: cloud cron or a local interval.

## Worktree procedure (the Handoff move -- project-local, never global)
- Detect first: compare `git rev-parse --git-dir` vs `--git-common-dir`; if they differ you
  may be in a linked worktree -- but confirm it is not a submodule
  (`git rev-parse --show-superproject-working-tree` non-empty implies submodule). If already
  isolated, skip creation.
- Create: prefer a native harness worktree tool; else `git worktree add`. Location priority:
  explicit user preference -> existing `.worktrees/` (wins over `worktrees/`) -> create
  `.worktrees/`. Hard gate before creating: `git check-ignore -q .worktrees` -- if not
  ignored, add it to `.gitignore` and commit first. On a sandbox permission error, tell the
  user and work in place.
- Clean up (provenance-gated): only remove a worktree under `.worktrees/` or `worktrees/`.
  Order: merge -> `cd` main root -> `git worktree remove` -> `git worktree prune` -> delete
  branch. Cleanup runs only on merge-and-delete or discard.

## Worktree status and sweep
Track each open worktree in `state/worktrees.md`, a plain markdown table:
`| path | branch | pattern | status | created |`, status one of
`active | rejected | escalated | merged`. Update the row's status the moment a worktree
is rejected or escalated -- never leave it silent. List stale candidates with:
```sh
awk -F'|' '$5 ~ /rejected|escalated/ {print $3, $6}' state/worktrees.md
```
which prints the branch and creation date of every rejected/escalated row; a human (or
the devops-engineer) confirms age from that date before running the existing cleanup
order above (merge -> `cd` main root -> `git worktree remove` -> `git worktree prune` ->
delete branch) on each. This never runs automatically -- it is a report, not an action,
matching the provenance gate already in place (only remove a worktree under
`.worktrees/` or `worktrees/`).

## State-file resume block (every `state/<name>.md`)
```
## Resume and Execution Handoff
1. selected plan/loop file path
2. last completed phase or step
3. gate/qa-engineer status (passed / rejected+reason / pending)
4. supporting context files loaded
5. next step for a fresh agent picking up mid-run
6. acting_on: <branch-or-PR-id this loop is currently working, or none>
```
On resume, cross-check these claims against git (trust git) and recover the cycle counter
from disk (never reset it).

## Multi-loop coordination
Before opening a worktree, grep every other `state/*.md` for a matching `acting_on:`
value; if found, skip this finding and log why instead of proceeding -- another loop is
already on it. Record what this loop is currently acting on as field 6 of its own resume
block above. This is a real gap once a second loop exists: two loops fixing the same
target minutes apart wastes tokens with nothing to show for it.

## Inbox-item response contract
Every item a loop routes to `inbox/` states the three actions a human can take: **confirm**
(approve as-is) / **change: `<free-text redirect>`** / **exit** (kill this item). The loop
reads this reply back on its next turn. **Consume-before-act:** the loop marks the item
consumed (frontmatter `status: consumed`, committed) BEFORE executing the chosen action --
never check-then-act with I/O in the gap. A runner that finds the marker already set reports
"already decided" and moves on, as an expected outcome, not an error.

## Local vs cloud tradeoff
- Cloud cron (GitHub Actions): survives a closed laptop, runs overnight, needs secrets and a
  headless CLI. Best for the daily triage loop.
- Local interval: no secrets to manage, immediate, but only runs while the machine is on.
  Best for interactive or on-demand loops.

## Loop readiness score (advisory, not a gate)
`scripts/loop-readiness.sh` prints a 0-100 score per `loops/*.loop.md` in the current
project: 20 points each for the five moves present, the five agentic-signals present, a
human-checkpoint line, a budget section with real (non-placeholder) values, and at least
one `state/metrics.md` row proving the loop has actually run. Levels: L0 Draft (<40), L1
Documented (40-59), L2 Wired (60-79), L3 Proven (80-100). Advisory only -- it never exits
nonzero and never blocks a build or a merge. No score, at any level, authorizes skipping
the human checkpoint; see `skills/sefi-orchestration/references/human-checkpoint.md`.

## State-sync drift check
`scripts/check-state-sync.sh` flags a `loops/*.loop.md` whose named state file is
missing, not yet created (normal before the first run), or missing its resume block --
run it after editing a loop spec and again before scheduling it. Advisory only, matching
this repo's report-don't-act convention for broad scans.

## Growth rule
Widen discovery before parallelism. More findings surfaced beats more workers racing.
