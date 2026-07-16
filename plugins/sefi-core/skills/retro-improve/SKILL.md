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
Review qa-engineer REJECTs, gate failures, and the knowledge-manager's
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

Self-test: every edit landed in a managed-by sefi-agents file the runtime actually loads,
changed <= 3 sentences, and passed the qa-engineer's pre-commit effectiveness check
against its cited failure evidence.
