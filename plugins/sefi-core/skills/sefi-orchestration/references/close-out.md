# close_out -- the canonical behavior

`close_out` is one of the five agentic-signals every loop spec declares. Until now it was
the only one declared everywhere and defined nowhere (`goal_intake` has
`references/goal-intake.md`; this file is the equivalent). An undefined signal is a label,
not a gate.

close_out is also where the memory vault gets its raw material. Before this file existed
the vault had a consumer with no producer: `knowledge-manager.md` reads
`memory/daily/*.md` as "the raw material" and distills it weekly, every other agent files
observations as "a decision note candidate for the knowledge-manager", and **nothing
wrote a daily note**. `/sefi:init` created `memory/daily/` and it stayed empty, so the
weekly distill was a permanent no-op and the SessionStart injection had nothing to inject.

## When it fires
At the end of a loop cycle, after the Persistence move and before the loop reschedules.
Also at the end of a distinct chunk of interactive work, when the session produced
something a later session would need to know.

Not per turn, and not per tool call. close_out fires once per cycle.

## What it does
The orchestrator (or the loop) dispatches the **knowledge-manager** -- never another agent,
never a hook -- to file the cycle's durable observations. The single-writer invariant is
unchanged: every other agent still only nominates candidates, and the knowledge-manager
still owns every byte written under `memory/`.

A hook cannot do this job. Persisting session content requires the memory-protocol privacy
filter to run first, and a deterministic shell hook cannot judge which bytes are a
credential, a client name, or a `<private>` block. That judgment is why the producer is an
agent dispatch rather than a `Stop` hook.

## What counts as durable
File it when it would change how a later session acts:
- a decision and the alternative that was rejected, with the reason
- a constraint discovered the hard way (an API's real rate limit, a build step that must
  run first, a test that is flaky for a known reason)
- a correction to something previously believed true here
- a recurring symptom seen for the second time (recurrence is the promotion signal)

Do NOT file: what was done step by step, anything reconstructable from the diff or from
`state/`, restatements of the plan, or tool output. That is what `state/` and
`.worktrees/logs/` are for, and mixing machine bookkeeping into the vault is what
memory-protocol forbids.

## How it writes
Through the existing memory-protocol WRITE path, unchanged:
1. Privacy filter first -- strip secrets, keys, and `<private>` blocks before anything is
   persisted.
2. Append to today's `memory/daily/YYYY-MM-DD.md` as `## HH:MM -- <topic>`, 3 lines max,
   plus `[[links]]`. Default `tier: trace`, `scope: session`.
3. Regenerate the router (`scripts/gen-router.sh`) so the next session's injection sees it.

close_out produces `tier: trace` daily notes and nothing else. It never writes to
`decisions/` directly and never promotes a tier. Promotion stays the knowledge-manager's
weekly recurrence-based job, so the ladder (trace -> policy -> fact) still earns each rung
from evidence rather than from one confident session.

## When nothing is durable
Log SKIP with a reason and write no note. An empty daily note is worse than none: it costs
a router line, an injection slice, and a distill pass, and it asserts that the cycle
produced something when it did not. SKIP is a conclusion, the same way it is in
retro-improve.

## Failure is not silent
If the dispatch fails or the vault is unwritable, say so in the cycle's output and park the
observation in `inbox/`. A close_out that quietly wrote nothing is indistinguishable from a
cycle with nothing to say -- which is exactly the failure this file exists to end.

Self-test: the cycle either appended a privacy-filtered daily note through the
knowledge-manager, or logged SKIP with a reason. Never neither.
