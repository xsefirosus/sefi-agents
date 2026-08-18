---
name: retro-improve
description: Use when running the self-improvement retro over qa-engineer rejects, gate failures, and metrics to propose bounded edits. Single-writer, append-only-safe self-improvement that edits only managed-by sefi-agents files and stops when improvement is disabled.
managed-by: sefi-agents
---

# Retro-Improve -- single-writer self-improvement

Two learning loops writing the same file produce conflicting edits. One writer per artifact
set. This skill is that single writer for `managed-by: sefi-agents` files.

User instructions always override this skill.
All factual output follows the anti-hallucination skill: cite or mark UNKNOWN, never guess.

agentic-signals: goal_intake, refusal_gate, verification, loop_discipline, close_out

## HARD GUARDS
You may edit only files whose frontmatter contains `managed-by: sefi-agents`. You may not
create new skills without a human-approved entry in `inbox/`. If `improvement.enabled` is
false in `sefi.config.yml`, output the proposed diff to `state/retro-<date>.md` and stop.
`managed-by` files are installed once per user, not per project, so the single-writer
invariant above holds only within one install: on a shared install, this project's metrics
would rewrite agents every other project loads, and every local guard here would still pass.
That is what `improvement.enabled: false` is for, and why `/sefi:init` sets it on any install
serving more than one project.
Never edit host-runtime memory, user config, or other plugins.

## Inputs (the scorecard)
Read `state/retro-ledger.md` FIRST, before selecting any target. It is this loop's memory
of its own edits, and without it the loop cannot tell that it already edited a file last
week, or that a human already rejected the exact proposal it is about to make again. Three
rules bind (full text and rationale in the ledger's own header):
- Churn guard: a target with an `applied` row in either of the last 2 runs is not eligible
  again; take the next-worst performer and log the skip.
- Rejection memory: never re-propose a `rejected` row -- escalate once to `inbox/` citing
  it if the evidence recurs.
- Evidence debt: a `pending-evidence` row blocks a new edit to that same target.

Then review qa-engineer REJECTs, gate failures, and the knowledge-manager's
`## Possible contradiction` flags. Read `state/metrics.md` as the scorecard -- worst
success rate first. A recurring routing-table miss (the engineering-manager escalating "no
table row matches" more than once for a similar trigger) is an explicit scorecard signal
too -- the routing table grows by precedent, not by a deterministic matcher, so this is
where that drift actually gets caught.

## Four additional guards (predecessor Loop-3 lessons)
- Bounded change: an improvement edits at most ~3 sentences per file per retro run
  (checkable: sentence-level set difference between old and new <= 3). Anything larger
  becomes a proposal in `inbox/`, not an edit. This is a fixed, absolute cap, not a
  percentage of the target file's size -- a percentage-growth cap still admits a large
  diff on an already-large file; a fixed sentence cap doesn't, and greps identically
  regardless of file size (a second, independent self-improvement system, NousResearch's
  hermes-agent-self-evolution, uses a 20%-of-baseline growth cap instead and gets the
  weaker guarantee).
- SKIP is a conclusion, not a shortcut: when the metrics show nothing worth changing, log
  `SKIP` with a stated, data-backed reason (e.g. "12/13 PASS over 4 weeks, no failure
  pattern") to `state/retro-<date>.md`. The history is complete either way.
- Single keyspace: the target is selected by `target-path` from `state/metrics.md`, and
  that exact path is the file edited. If the worst performer's path does not resolve to a
  `managed-by: sefi-agents` file, that is a wiring bug to flag to `inbox/` -- never a
  silent no-op.
- Edit what the runtime loads: before editing, confirm the target file is actually
  reachable by the harness (listed in `skills/sefi-orchestration/references/roster.md` or a loaded skill directory).
  Improving an unwired copy changes nothing.
- Verify before applying (not after): hand the proposed edit to the qa-engineer BEFORE
  it is committed, together with the specific failure evidence it targets (the REJECT,
  gate failure, or contradiction row from the scorecard). The qa-engineer judges two
  things: does this edit plausibly prevent that specific failure, and does a re-read of
  the whole file confirm no other stated duty was weakened or removed. A REJECT on
  either makes the edit an `inbox/` proposal, never a commit -- the retro loop cannot
  self-certify its own edit as effective, the same way the software-engineer cannot
  self-certify a slice.
  - A cheap deterministic pre-filter runs BEFORE that judgment call, same ordering
    principle as `check-bar.sh` / `check-reply.sh` / `gate.sh`: deterministic checks
    first, spend the LLM call second. Run `${CLAUDE_PLUGIN_ROOT}/scripts/check-structure-diff.sh
    <target-before> <target-after>` on the proposed edit; a removed or changed
    structural field (a stripped `tools:` entry, a changed `tier:`, a missing
    anti-hallucination pointer) becomes cited evidence for the qa-engineer's own call,
    never a silent auto-block -- same additive relationship bar-comparison has to Done
    Criteria. If the target is named in `routing-table.md`, also re-run the EXISTING
    `validate-routing.sh` against the proposed edit; if the target IS
    `routing-table.md` itself, run it directly. No new routing-fixture mechanism is
    built -- the one that already exists (`routing-cases.txt`) is reused.
  - This does not replace the ledger's revert rule below: that rule is slow and
    statistical by design, needing 3-5 real qa-engineer verdicts accumulated over live
    dispatches after an edit ships. This pre-filter is instant and deterministic,
    catching a structural or routing regression before the edit is even committed.
    Neither replaces the other; if the two ever start catching the identical failure
    shape, delete this one -- same rule already applied when `prompt-engineer` was
    added against `goal_intake`.

## Ledger append (at edit time, not afterwards)
Every retro decision appends one row to `state/retro-ledger.md` -- `applied`, `proposed`,
`rejected` and `skip` alike -- carrying the target-path, the commit SHA of the applied
edit, the motivating evidence, and the `before` PASS rate from `state/metrics.md`. Write it
when the decision is made: the `before` value and the evidence pointer exist only at that
moment, and a run that skips the append is permanently un-analyzable afterwards. The SHA is
what makes an edit undoable at all.

## Reversibility (the other half of the loop)
Applying an edit without being able to un-apply it is a ratchet, not learning. The revert
rule -- evaluation window, minimum data, regression definition -- is fixed in
`state/retro-ledger.md`, written deliberately before any metrics existed so it could not be
fitted to them. A detected regression becomes an `inbox/` proposal naming the exact
`git revert <sha>`; it is never applied automatically, because a revert is still a commit
and `human-checkpoint.md` is unconditional.

## Commit message format
Every applied edit's commit message states the metric that motivated it and the
before/after values from `state/metrics.md` (e.g. "qa-engineer PASS rate 6/10 -> target:
address recurring REJECT reason"), or `UNKNOWN` if no measured before/after value exists
yet -- never a vague "improved X" with no cited evidence.

## Common Rationalizations
| Excuse | Rebuttal |
|---|---|
| "This rewrite is a big improvement." | Bounded change: <=3 sentences/file, or it is an inbox proposal. |
| "Nothing to change, moving on." | SKIP is logged with a data-backed reason, not skipped silently. |
| "The worst path isn't ours, no-op." | An unresolvable target is a wiring bug for inbox/, not a no-op. |
| "I'll add a new skill to fix this." | New skills need a human-approved inbox/ entry first. |
| "This file is still the worst performer, edit it again." | Churn guard: an `applied` row in the last 2 runs makes it ineligible. |
| "The human rejected it, but the bug is still there." | Rejection memory: escalate to inbox/ citing the row, never silently retry. |
| "The edit made things worse, revert it." | A revert is a commit: propose it to inbox/, never self-apply. |

Self-test: every edit landed in a managed-by sefi-agents file the runtime actually loads,
changed <= 3 sentences, passed the qa-engineer's pre-commit effectiveness check against its
cited failure evidence, and appended a row to state/retro-ledger.md carrying the SHA that
makes it revertible.
