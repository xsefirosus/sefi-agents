# Goal Intake -- the canonical goal_intake behavior

This is the one place the goal_intake signal's actual behavior is defined. Every agent
or skill that declares `goal_intake` in its agentic-signals line links here in one line
and never restates it.

## The rule
Before committing to a plan or an action, when a work item lacks a testable "done"
condition, an exact scope, or a concrete value a fix depends on: ask ONE question at a
time. Push for exact/numeric values ("make it fast" -> "what p95 latency, in ms?"), never
accept a vague answer as final. If no blocking question resolves within the turn,
escalate instead of guessing: write `- [ ] OQ: <question>` and mark the item
`needs-human`, with an `Open questions: <N> (needs-human)` line in the output. Never
proceed on an assumption in place of an answer.

## Why (external precedent)
cobusgreyling/loop-engineering's `SKILL.md.loop-intake` template independently arrived at
the same three rules (one question at a time, push for exact values, escalate rather than
guess) as a pre-triage gate; sefi-agents already declared the `goal_intake` signal in its
agentic-signals block but had never defined the behavior behind it -- this closes that gap.

## Binary self-test
Every plan or action with an unresolved ambiguity has either a concrete answer or an
`- [ ] OQ:` line and a `needs-human` mark. Proceeding on a guessed value is a violation.
