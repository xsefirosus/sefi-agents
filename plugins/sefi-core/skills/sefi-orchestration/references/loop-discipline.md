# Loop Discipline -- the canonical loop_discipline behavior

This is the one place the loop_discipline signal's actual behavior is defined, the same
way `goal-intake.md` defines `goal_intake` and `close-out.md` defines `close_out`. Every
agent or skill that declares `loop_discipline` in its agentic-signals line links here in
one line and never restates it.

## The rule
A loop or repeated cycle obeys its own stop conditions, escalation thresholds, and state
precedence rules exactly, every cycle, with no silent skip and no silent scope-widening.
SKIP, degrade, and escalate are logged conclusions the loop reaches deliberately, never
omissions it drifts into.

## When it fires
At every cycle boundary and every tripwire check within a cycle -- not only when
something goes wrong. A cycle that finds nothing to do still logs SKIP with a reason; a
cycle that hits a threshold still logs the degrade or escalate it took, not just the
outcome.

## Why (grounded in the declaring skills)
- `loop-engineering`'s deterministic tripwires are loop_discipline's enforcement layer: the
  repetition detector (same tool + same args twice in a row forces a stronger model or an
  escalation) and the qa-engineer's two separate circuit-breaker counters (stagnation on 3x
  identical error, no-progress on 5x any failure) fire without waiting for an LLM judgment
  call. Its Hard rules bind the same way: git-reconciliation trust (a `state/*.md` claim
  that disagrees with git loses to git) and cycle-count preservation (a resumed loop reads
  its counter from disk, never resets it) are precedence rules a cycle may not silently
  override. The four predecessor-earned rules -- consume-before-act, non-retryable
  harness-limit notices, the metrics append after every verdict, and per-operation timeout
  classes -- are each a specific, previously-violated discipline rule now made explicit.
- `retro-improve`'s bounded-change cap (<=3 sentences per file per run) and churn guard are
  loop_discipline's scope-widening limits made concrete; rejection memory and evidence debt
  are its state-precedence rules (a `rejected` or `pending-evidence` row overrides a fresh
  proposal); and "SKIP is a conclusion, not a shortcut" is this file's own rule stated
  first, in the file where the pattern was named.
- `security-review`'s severity-scaled response times -- Critical: `inbox/` within 2 minutes
  or before turn end, whichever is sooner -- are loop_discipline's escalation threshold at
  its tightest bound: a deadline that must be met exactly, not approximately.

## Binary self-test
Every cycle either completed within its stated stop conditions and thresholds, or logged
an explicit SKIP/degrade/escalate with a reason. A cycle that silently skipped a check or
silently widened its own scope is a violation.
