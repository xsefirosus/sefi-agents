## Objective
Add a 14th agent, `prompt-engineer`, that runs before the engineering-manager opens the
routing table. It receives the raw interactive human message, restates it as one or more
unambiguous single-intent statements, surfaces only constraints the user actually stated,
and hands the result to the EM with a non-binding suggested trigger-type label. It never
routes, never plans, never writes a file, and never invents scope.

## Steps
- [ ] 1. Write `plugins/sefi-core/agents/prompt-engineer.md`. Tier `low` (Claude Code: haiku) -- high-frequency, bounded-output work, same cost class as research-analyst and support-engineer, not the build/judge tier. Tools: Read, Grep, Glob only; no Write/Edit/Bash -- it restates, it does not build or persist. Protocol: (a) read the raw message once; (b) resolve pronouns and split a bundled multi-intent message into its constituent single-intent asks; (c) surface explicit constraints verbatim-sourced only, never inferred or invented; (d) attach a non-binding suggested trigger-type label per `routing-table.md`'s existing rows, for the EM's convenience, never a routing decision itself; (e) if genuinely irreducibly ambiguous, escalate via the existing `goal_intake` rule (ask ONE question) rather than inventing a second clarification mechanism -- reuse, not rewrite. Output inline (FINDINGS-digest shape, no state/ file), matching research-analyst's pattern, since its output is consumed the same turn by the EM. Declares `goal_intake` in agentic-signals, linking the same canonical `goal-intake.md` product-manager already links -- one rule, two legitimate call sites (routing-clarity here, planning-clarity there). Skipped entirely for a non-interactive or scheduled trigger, via the SAME `skip_clarification` / `non_interactive` flag `goal_intake` already honors -- no new flag invented. (needs: -)
- [ ] 2. Add a "Stage 0" paragraph to `sefi-orchestration/SKILL.md`'s Dispatch section: an interactive human message passes through `prompt-engineer` first; the EM then resolves the restated intent(s) against the table. States the skip condition explicitly so a reader does not have to infer it from goal-intake.md. (needs: 1)
- [ ] 3. Update `engineering-manager.md`'s Inputs line: "the incoming request" is typically prompt-engineer's restated output on an interactive turn, the raw trigger unchanged on a scheduled one. One line, not a rewrite of the Role section. (needs: 1)
- [ ] 4. Add a `prompt-engineer` row to `skills/sefi-orchestration/references/roster.md` so `validate-no-orphans.sh` resolves it. (needs: 1)
- [ ] 5. Update every "13 agents" prose claim to "14": `README.md` (title text, heading anchor, opening line, the team table) and `plugins/sefi-core/README.md`. `validate-doc-counts.sh` re-derives the count from disk and checks prose against it -- it needs the new number written, not a script change. (needs: 1)
- [ ] 6. CHANGELOG entry (0.3.1) naming the new agent and the boundary decision in step 1(e): why this does not duplicate goal_intake or product-manager. (needs: 2, 3, 4, 5)
- [ ] 7. Run `run-all.sh` in full, including `validate-token-budget.sh` (a 14th agent raises the cap to 14x640=8960, so this is self-funded against the existing 13-agent total of 8222, not squeezed out of the 98-word headroom A2 depends on) and `validate-model-map.sh` (tier `low` already resolves on every harness; no model-map edit needed). (needs: 6)

## Files Touched
plugins/sefi-core/agents/prompt-engineer.md; plugins/sefi-core/skills/sefi-orchestration/SKILL.md; plugins/sefi-core/agents/engineering-manager.md; plugins/sefi-core/skills/sefi-orchestration/references/roster.md; README.md; plugins/sefi-core/README.md; CHANGELOG.md

## Requires Tools
none

## Risks
The clearest way this goes wrong is scope creep into goal_intake's or product-manager's job. The boundary this plan draws: prompt-engineer decides whether the request is clear enough to ROUTE (one sentence, one intent, real constraints only); goal_intake (still owned by product-manager) decides whether it is clear enough to PLAN (a testable Done Criteria, an exact scope, a concrete value). If those two ever start asking the same question, the newer one should be deleted, not both kept. Second risk: prompt-engineer must never become a 16th routing-table row -- it precedes the table, it is not triggered by it, and conflating the two would put a chicken before its own egg. Third: this is the first agent added since the roster was declared "13" everywhere; step 5's file list may be incomplete, since no prior work in this repo has added an agent and the full set of "13" mentions has never been enumerated.

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` passes with `agents=14` reported by `validate-doc-counts.sh`, and `validate-token-budget.sh` reports the new total against a `14 x 640 = 8960` cap with no other agent file needing to shrink.
