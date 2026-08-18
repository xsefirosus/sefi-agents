# Scope Boundary -- produce your own deliverable, never another agent's

The one place this rule is stated in full. Agents link here in one line and never restate
it (same pattern as `goal-intake.md`, `close-out.md`, `human-checkpoint.md`).

## The rule
Your `## Output contract` is a ceiling, not a floor. Emit exactly what it names and stop.
A deliverable that belongs to another agent is a contract violation even when it is
correct, even when it is good, and even when producing it feels more helpful than naming
who owns it. Routing exists so the right agent does the work under the right gates; an
agent that answers outside its lane has skipped those gates on the user's behalf without
telling them.

Being unable to perform an action is not permission to perform it a different way. A
read-only agent that cannot write a file also cannot deliver that file's contents inline:
the tool whitelist withheld the capability deliberately, and routing around it with prose
defeats the whitelist without removing it. The correct move is to name the agent that owns
the work and stop.

## Common Rationalizations
| Excuse | Rebuttal |
|---|---|
| "I have no write tool, so I'll produce the artifact inline instead." | The missing tool is the boundary, not an obstacle to route around. Name the owning agent. |
| "Dispatching costs a round trip; I already know the answer." | The round trip IS the gate. Skipping it removes the reviewing agent, not just the delay. |
| "The user asked me directly, so they want it from me." | They asked the roster, not the file. Route it; the deliverable arrives either way. |
| "Refusing looks unhelpful." | An unrequested deliverable is a contract violation, not helpfulness. Naming the owner is the help. |
| "It's a small artifact, not worth a handoff." | Size is not the criterion; ownership is. Triviality is judged by the gate, not the producer. |

## Enforcement, stated honestly
`${CLAUDE_PLUGIN_ROOT}/scripts/check-reply.sh` gates this on the DISPATCHED path: the engineering-manager runs it
on a returned reply, and a nonzero exit blocks acceptance. It derives the expected labels
from the agent's own contract, bounds verbosity against `per_agent_return_tokens`, and
flags full foreign deliverables in a read-only agent's reply.

It does NOT cover a human invoking a specialist agent DIRECTLY. There is no orchestrator in
that path, so no gate runs, and prose plus the tool whitelist are the only defenses left.
The live failure this file exists because of (2026-08-17) came through exactly that path.
Saying the gate closes it would be the overclaim the anti-hallucination skill forbids, so it
is written down here instead: on a direct invocation, this rule is honored, not enforced.

Self-test: every reply contains only what its own `## Output contract` names, and work
belonging to another agent is named and routed rather than produced.
