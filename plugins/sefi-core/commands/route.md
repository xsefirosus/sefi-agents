---
description: Deterministically load the sefi-orchestration skill and route one task -- for when the auto-trigger might not fire on its own.
argument-hint: [task description]
---

# /sefi:route

`sefi-orchestration` is model-invoked: Claude Code loads it only when its own judgment
matches your message against the skill's description, and that judgment can miss even on
a task that plainly needed routing (live example: an entire session doing textbook
engineering-manager work -- reading a plan, dispatching subagents, deciding what needs a
human call -- without the skill ever firing). This command exists to skip the guess:
invoking it loads the skill and dispatches, with no auto-trigger involved.

1. Invoke the `sefi-orchestration` skill now, unconditionally -- do not decide whether it
   "seems needed"; that judgment call is the exact failure mode this command exists to
   bypass.
2. Task = `$ARGUMENTS`. If empty, ask ONE question for what to route (per `goal_intake`,
   `skills/sefi-orchestration/references/goal-intake.md`) -- never guess a task from
   surrounding conversation just because one is available.
3. Follow the skill's Dispatch section exactly: Stage 0 (`prompt-engineer` restates an
   interactive message into single-intent asks) unless this is itself a non-interactive or
   scheduled trigger, then resolve the restated intent(s) against
   `skills/sefi-orchestration/references/routing-table.md`, gate the handoff with
   `${CLAUDE_PLUGIN_ROOT}/scripts/check-handoff.sh`, and dispatch the resolved agent via
   the harness's native subagent-dispatch tool (`harness-actions.md`'s "Dispatch a
   subagent" row -- Task/subagent on Claude Code).
4. This command does not do the work itself, same as engineering-manager: it routes and
   dispatches, then reports the dispatch record per `engineering-manager.md`'s own Output
   contract. It never edits files, and a routing miss still goes to `inbox/` per that
   agent's Escalation rule -- this command changes how routing gets INVOKED, not the rules
   once it has been.
