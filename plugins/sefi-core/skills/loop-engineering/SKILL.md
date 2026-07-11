---
name: loop-engineering
description: Use when designing, running, or resuming a loop, or mapping the five moves to repo mechanics. Covers discovery, handoff via worktrees, verification, persistence, and scheduling, plus grep-countable stop conditions, deterministic tripwires, and the git-trust and cycle-count resume rules.
managed-by: sefi-agents
---

# Loop Engineering

A loop discovers work, hands it off, verifies it, persists state, and reschedules itself.
Every loop implements all five moves. This skill maps them to repo mechanics.

User instructions always override this skill.
All factual output follows the anti-hallucination skill: cite or mark UNKNOWN, never guess.

agentic-signals: goal_intake, refusal_gate, verification, loop_discipline, close_out

## The five moves (mapped to repo mechanics)
- Discovery: a skill invoked by the automation reads CI / issues / commits / state and
  judges actionability.
- Handoff: one git worktree per finding, per the worktree procedure in `docs/LOOPS.md`.
- Verification: the qa-engineer plus an executed stop condition, judged separately from
  the generator.
- Persistence: `state/*.md` committed, carrying a cross-iteration notes bridge (what the
  next iteration must know).
- Scheduling: cloud cron or a local interval.

## Stop condition = a grep-countable artifact, not a self-declaration
The product-manager's numbered-checkbox plan is "done" only when every box is checked -- counted
by grep, never the generator declaring "I'm done." (AutoGPT's `finish`-tool self-completion
is the anti-pattern; a predecessor's 184-green-tests-half-unwired build is the first-party proof
that self-declared done lies.)

## Deterministic tripwires (zero LLM cost)
- Repetition detector: same tool + same args twice in a row -> force a stronger model or
  escalate.
- The qa-engineer's instability score (+1 per revert / unrelated-file fix / repeated
  failed action; stop at > 3).

## Hard rules
- Git-reconciliation trust: a `state/*.md` claim that disagrees with git loses to git.
- Cycle-count preservation: a resumed loop reads its counter from disk, never resets it.

## Four predecessor-earned rules (each observed live)
- Consume-before-act: when acting on a human decision or any once-only trigger, write the
  consumed marker FIRST -- `status: consumed` in the item's frontmatter (or rename
  `*.consumed.md`) and commit -- before the action. Never check-then-act with I/O in the
  gap. A later runner that finds the marker skips with "already decided," an expected
  outcome, never an error.
- Harness-limit notices are non-retryable: a usage/session-limit notice (e.g. the Claude
  CLI's plain-text "session limit" -- not JSON, not an exit code) repeats until the window
  resets. Detect it, don't retry, write the resume block, park the item in `inbox/` with
  reason `harness-limit`, and stop cleanly.
- Metrics append (the persistence move): after every qa-engineer verdict, append one row to
  `state/metrics.md` (`| date | target-path | loop | verdict | retries | note |`).
  Append-only, keyed by the plugin-relative FILE PATH of the agent/skill -- the same path
  the retro loop edits, so there is one keyspace by construction.
- Per-operation timeout classes: a long legitimate operation (multi-task dispatch, full
  test suite) gets its own larger timeout, not the default (a 300s default killed a live
  12-task dispatch; the fix was a separate 900s budget for that call class).

## Growth rule
Widen discovery before parallelism. More findings surfaced beats more workers racing.

Self-test: the loop's stop condition is a grep-countable artifact, and its resume block
survives a cold restart.
