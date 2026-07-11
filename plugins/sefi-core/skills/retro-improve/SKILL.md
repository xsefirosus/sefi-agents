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
Never edit host-runtime memory, user config, or other plugins.

## Inputs (the scorecard)
Review qa-engineer REJECTs, gate failures, and the knowledge-manager's
`## Possible contradiction` flags. Read `state/metrics.md` as the scorecard -- worst
success rate first.

## Four additional guards (predecessor Loop-3 lessons)
- Bounded change: an improvement edits at most ~3 sentences per file per retro run
  (checkable: sentence-level set difference between old and new <= 3). Anything larger
  becomes a proposal in `inbox/`, not an edit.
- SKIP is a conclusion, not a shortcut: when the metrics show nothing worth changing, log
  `SKIP` with a stated, data-backed reason (e.g. "12/13 PASS over 4 weeks, no failure
  pattern") to `state/retro-<date>.md`. The history is complete either way.
- Single keyspace: the target is selected by `target-path` from `state/metrics.md`, and
  that exact path is the file edited. If the worst performer's path does not resolve to a
  `managed-by: sefi-agents` file, that is a wiring bug to flag to `inbox/` -- never a
  silent no-op.
- Edit what the runtime loads: before editing, confirm the target file is actually
  reachable by the harness (listed in `references/roster.md` or a loaded skill directory).
  Improving an unwired copy changes nothing.

## Common Rationalizations
| Excuse | Rebuttal |
|---|---|
| "This rewrite is a big improvement." | Bounded change: <=3 sentences/file, or it is an inbox proposal. |
| "Nothing to change, moving on." | SKIP is logged with a data-backed reason, not skipped silently. |
| "The worst path isn't ours, no-op." | An unresolvable target is a wiring bug for inbox/, not a no-op. |
| "I'll add a new skill to fix this." | New skills need a human-approved inbox/ entry first. |

Self-test: every edit landed in a managed-by sefi-agents file the runtime actually loads,
and changed <= 3 sentences.
