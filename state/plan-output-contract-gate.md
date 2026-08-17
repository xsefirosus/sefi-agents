## Objective
Measure output-contract compliance instead of asking for it. `prompt-engineer` produced a
full HTML/CSS artifact -- `ui-ux-designer`'s and `software-engineer`'s deliverable -- against
a contract reading "Reply with exactly this digest and nothing else". A roster audit found
that agent already carried the STRONGEST prose defenses available: the tightest output
contract in the read-only set, an explicit negative boundary ("never route, never plan,
never write a file, never invent scope"), a machine-invoked clause, and a correct tool
whitelist that did hold (no file was written -- only content leaked). Prose was at its
ceiling and still failed, so more prose is not the fix. `per_agent_return_tokens` has sat
in `config/budget.yml` since v0.2.1 enforced by nothing; this wires it.

## Steps
- [ ] 1. Write `scripts/check-reply.sh <agent-file> <reply-file>`. Derive the expected section labels from the agent's OWN `## Output contract` (single source of truth, same principle as validate-doc-counts deriving counts from disk rather than a hand-kept table). Check: (a) every declared label present; (b) word count against `per_agent_return_tokens` from `config/budget.yml`, named as a word-count PROXY for tokens, never claimed as a token count; (c) foreign-deliverable markers (`<!DOCTYPE`, `<html`, a `## Done Criteria` plan skeleton) for read-only agents only. Exit codes follow budget-check.sh's precedent: 0 clean, 1 contract violated, 2 usage, 3 CANNOT-CHECK (the agent declares no parseable labels -- distinct from a clean pass, or the gate certifies a check it never ran). (needs: -)
- [ ] 2. Write `skills/sefi-orchestration/references/scope-boundary.md`: the canonical stay-in-lane rule plus a rationalization table carrying the excuse observed live -- "I have no write tool, so I will be helpful and produce the artifact inline instead" -- and its rebuttal (name the agent that owns it; an unrequested deliverable is a contract violation, not helpfulness). One shared reference rather than four per-agent tables: four tables cost ~260 words against 149 of headroom, and this repo already resolves exactly that with one canonical file plus one-line links (goal-intake.md, close-out.md). (needs: -)
- [ ] 3. Name `scope-boundary.md` in `sefi-orchestration/SKILL.md`'s References so `validate-no-orphans.sh` resolves it. (needs: 2)
- [ ] 4. Link `scope-boundary.md` in one line each from the four read-only agents with no rationalization table, which the audit identified as the exposed set: `prompt-engineer`, `engineering-manager`, `research-analyst`, `support-engineer`. Cap each at 12 words (~48 total) against 149 words of headroom. (needs: 2)
- [ ] 5. Wire the gate into `engineering-manager.md`'s protocol: run `check-reply.sh` on a dispatched agent's reply before accepting it; a nonzero exit sends the reply back once, then to `inbox/` -- the same shape as the existing check-handoff.sh rule, applied to the inbound side of a dispatch instead of the outbound. (needs: 1)
- [ ] 6. Add regression tests to `scripts/ci/test-scripts.sh`, anchored on the REAL artifact: a well-formed prompt-engineer digest exits 0; that same digest plus a full HTML document exits 1; an over-budget reply exits 1; a reply missing a declared label exits 1; a qa-engineer `VERDICT: PASS` reply exits 0 (guarding against a gate that only accepts one agent's shape); support-engineer's table-shaped contract exits 3, not a false 1. (needs: 1)
- [ ] 7. State the enforcement boundary plainly in `scope-boundary.md`: this gate covers the DISPATCHED path, where an orchestrator exists to run it. A human invoking a specialist agent DIRECTLY has no orchestrator in the loop -- nothing runs there, and prose plus the tool whitelist remain the only defenses. The live failure came through that direct path, so claiming the gate closes it would be precisely the overclaim this repo's anti-hallucination skill exists to prevent. (needs: 2, 5)
- [ ] 8. Run `run-all.sh`, confirm green including `validate-token-budget`, and add the CHANGELOG entry. (needs: 3, 4, 6, 7)

## Files Touched
plugins/sefi-core/scripts/check-reply.sh; plugins/sefi-core/skills/sefi-orchestration/references/scope-boundary.md; plugins/sefi-core/skills/sefi-orchestration/SKILL.md; plugins/sefi-core/agents/prompt-engineer.md; plugins/sefi-core/agents/engineering-manager.md; plugins/sefi-core/agents/research-analyst.md; plugins/sefi-core/agents/support-engineer.md; plugins/sefi-core/scripts/ci/test-scripts.sh; CHANGELOG.md

## Requires Tools
awk

## Risks
The gate cannot run on a direct human-to-specialist invocation, which is the exact path the
live failure came through -- step 7 states that rather than letting the fix imply more
coverage than it has. Label derivation is brittle where a contract is prose- or
table-shaped rather than `LABEL:` lines (support-engineer's is a table description): that
case must exit 3 CANNOT-CHECK, never a false 1, because a gate that cries wolf on valid
replies trains the engineering-manager to ignore it -- the failure mode that makes a gate
worse than none. Foreign-deliverable detection is heuristic and scoped narrowly to
read-only agents for the same reason: technical-writer legitimately emits markdown and a
research digest may legitimately quote code, so the marker list stays at full-document
shapes, never "any fenced block". Word count is a proxy for tokens, not tokens; the ~150
figure is a bound on verbosity, not an accounting claim. Verbose self-narration on a free
model is only partly addressed here -- a cheap model will still think out loud, and this
bounds what it may RETURN, not what it may say while working.

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` passes including `validate-token-budget`,
and `check-reply.sh` exits 1 on the actual observed failure (prompt-engineer's digest
followed by a full HTML document) while exiting 0 on that same digest alone.
