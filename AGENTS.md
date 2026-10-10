# Collaboration Instructions

## Sefi routing

This project runs the sefi-agents chain. Before starting work, invoke the
`sefi-orchestration` skill and resolve the request against its routing table rather
than implementing it directly.

Hermes has no session-start hook, so this file is what puts the routing rule in front
of you: it is read into the system prompt on every session. On Claude Code, OpenCode,
and Codex a session-start hook already does this, and the rule here is consistent with
it rather than additional to it.

To load the skill deterministically instead of relying on description matching, invoke
`/sefi:route` (`/sefi-route` on Hermes).

- Treat a user's request as authorization for the directly related work needed to finish it
  well. This includes consistency fixes, documentation updates, tests, validation, and
  release bookkeeping that accurately reflect the requested change.
- Make reasonable, low-risk decisions within that scope. Report what changed and any
  material tradeoff clearly when handing the work back.
- Ask before changing the product's intended behavior beyond the request, redesigning an
  architecture, adding a dependency or service, changing permissions or credentials, or
  taking an irreversible external action not already requested.
- If you find an unrelated risk, defect, or improvement, briefly explain it and recommend
  a next step. Do not let it block the requested work unless it makes that work unsafe.

# Sefi routing

Route every request through the `sefi-orchestration` skill before acting: follow
its Stage 0 and routing table, use the required skills and budgets, and dispatch
the specialists its route requires. A genuinely trivial request may use that
skill's documented exception. Explicit user instructions override this block.
`sefi-orchestration` is model-invoked, not automatic -- when its auto-trigger
does not fire, invoke it deterministically via the route command (`/sefi:route`,
spelled `sefi-route` on Hermes).
