## Objective
Give `retro-improve`'s "Verify before applying" step a second, deterministic, instant
pre-check alongside the qa-engineer's judgment call -- not a port of the source proposal's
JSON-baseline `SkillRegressionTester`, which does not map onto this repo cleanly (see
Risks). The genuinely non-redundant sliver, found by evaluating against what already
exists rather than assumed: a structural-invariant diff (did the edit silently strip a
`tools:` entry, a `tier:`, the anti-hallucination pointer) plus reuse of the ALREADY-SHIPPED
`validate-routing.sh` / `routing-cases.txt` fixture pair for routing-relevant edits. Both
answer the source doc's three open questions with evidence, not invention.

## Steps
- [x] 1. Write `scripts/check-structure-diff.sh <before-file> <after-file>`. Extracts a deterministic fingerprint from each file: frontmatter keys present, `tools:`/`disallowedTools:` values, `tier:`, the `agentic-signals:` line if present, and whether the anti-hallucination pointer string is present. Diffs before vs after per field. An ADDITION is never an error -- agents legitimately gain fields over time (this exact repo added `tier:` and `agentic-signals:` to the whole roster mid-project). Only a REMOVAL or a CHANGE to an existing key is flagged, since silently losing a capability is the actual regression shape this exists to catch -- the same shape `validate-config-wired.sh` catches for config keys, applied to agent/skill frontmatter instead. Exit 0 no unexpected removal/change, 1 one or more flagged, 2 usage. (needs: -)
- [x] 2. Wire step 1 into `retro-improve/SKILL.md`'s "Verify before applying" step, explicitly as a cheap pre-filter that runs BEFORE the qa-engineer's judgment call -- same ordering principle as `check-bar.sh`/`check-reply.sh`/`gate.sh`: deterministic checks first, spend the LLM judgment call second. If the edit target is named in `routing-table.md`, also re-run the EXISTING `validate-routing.sh` against the proposed edit -- no new routing-fixture mechanism is built; the one that already exists is reused. A flagged structural or routing regression becomes part of the qa-engineer's cited evidence for its own call, never a silent auto-block -- same additive-not-replacing relationship bar-comparison already has to Done Criteria. (needs: 1)
- [x] 3. State explicitly, in `retro-improve/SKILL.md` near this addition, why it does not duplicate `state/retro-ledger.md`'s existing revert rule: the ledger's revert rule is slow and statistical by design (it needs 3-5 real qa-engineer verdicts accumulated over live dispatches AFTER the edit ships, per its own stated evaluation window); this is instant and deterministic, catching a structural regression BEFORE the edit is even committed. Neither replaces the other. If the two ever start catching the identical failure shape, delete this one -- same rule this session already applied when adding `prompt-engineer` against `goal_intake`. (needs: 2)
- [x] 4. Regression tests in `scripts/ci/test-scripts.sh`: an addition-only edit (a new frontmatter key) passes clean; an edit that removes `Bash` from a `tools:` line is flagged; an edit that strips the anti-hallucination pointer string is flagged; a routing-table edit that breaks an existing `routing-cases.txt` fixture is caught via the re-run in step 2, not a new mechanism. At least 5 assertions, at least one proven via re-break/restore. (needs: 1, 2)
- [x] 5. CHANGELOG entry (0.3.10) naming the scope decision in the Objective explicitly: structural/routing regressions only, not LLM-output fixture testing. (needs: 3, 4)
- [x] 6. Run `run-all.sh` in full. (needs: 5)

## Files Touched
plugins/sefi-core/scripts/check-structure-diff.sh; plugins/sefi-core/skills/retro-improve/SKILL.md; plugins/sefi-core/scripts/ci/test-scripts.sh; CHANGELOG.md

## Requires Tools
git

## Risks
The source proposal's actual shape -- stored `(input, expected_output)` pairs, diffed after running an `executor_func` -- does not port to this repo's agents, and this plan deliberately does not attempt it: sefi-agents' agents are LLM-driven markdown prose, not deterministic functions, so there is no `executor_func` that reproduces byte-identical output for a stored input the way code does. That is not a gap to close; it is the source doc's own flagged doubt ("may be a deliberate design choice... worth asking, not assuming a gap"), resolved here by finding the sliver that IS deterministically testable (structure, and routing) rather than forcing the whole mechanism through. If this scoping turns out to be wrong -- if there is a real, deterministic input/output relationship for some skill this plan did not consider -- that is new evidence for a future plan, not a reason to widen this one speculatively. Second risk: step 2's routing re-run only fires when the target is named in `routing-table.md`; a routing-relevant change that never touches a named agent (e.g., a routing-table row edit itself) must also trigger it -- confirm both directions before calling step 2 done, not just the agent-file direction. Third: `retro-improve/SKILL.md` has ample line headroom (110/300) so this is not word-budget-constrained the way agent files are, but keep the new material scoped to the "Verify before applying" section rather than spreading edits across the file.

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` passes with the new assertions included; `check-structure-diff.sh` correctly flags a removed `tools:` entry and a stripped anti-hallucination pointer in a regression test, passes clean on an addition-only edit, and a routing-table edit that breaks a `routing-cases.txt` fixture is caught by the existing `validate-routing.sh` re-run wired in step 2.
