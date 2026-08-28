# Refusal Gate -- the canonical refusal_gate behavior

This is the one place the refusal_gate signal's actual behavior is defined, the same way
`goal-intake.md` defines `goal_intake` and `close-out.md` defines `close_out`. Every agent
or skill that declares `refusal_gate` in its agentic-signals line links here in one line
and never restates it.

## The rule
Before acting, check whether the action is inside this agent or skill's granted authority
and declared tool/scope boundary. If it is not, stop -- either degrade to a stated reduced
scope or escalate to `inbox/` rather than proceeding on an assumption. A silent partial
action framed as a full one is a violation of this gate even when the partial action is
individually harmless.

## When it fires
Before any action that touches a tool, file, or scope the agent's own spec did not
explicitly grant -- not after the action, as a cleanup step. The check happens at the
boundary, the same way `security-review`'s halt-and-escalate fires on the finding, not
after the diff has already shipped.

## Why (grounded in the declaring skills)
- `retro-improve`'s HARD GUARDS are refusal_gate already in force under a different name:
  edit only `managed-by: sefi-agents` files, never create a new skill without a
  human-approved `inbox/` entry, and never edit host-runtime memory, user config, or other
  plugins. Each is a boundary check that runs before the edit, not a review after it.
- `loop-engineering`'s "probe before you grant" rule is the same gate applied to tools: a
  loop may not assume an undeclared external command. Presence is not health -- a probe
  result of BROKEN or MISSING forces the loop to run at stated reduced scope, naming the
  degraded move and the tool, rather than silently proceeding as if the tool worked.
- `security-review`'s Critical-severity behavior -- halt the slice, `inbox/` within 2
  minutes or before turn end -- is refusal_gate's escalation path at its most urgent, and
  its never-auto-merge line pointing at `human-checkpoint.md` is the same rule applied to
  the single highest-stakes action a loop can take.

## Binary self-test
Every action taken was inside a declared authority/tool/scope boundary, or the agent
stopped and either degraded at stated reduced scope or escalated to `inbox/`. A silent
assumption in place of either is a violation.
