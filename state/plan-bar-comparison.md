## Objective
Add bar-comparison as an OPTIONAL qa-engineer evidence type. When a real external
artifact exists, a verdict may cite a blind side-by-side against it, gated by a
Named / Fetchable / Comparable test so an unreachable bar cannot become a hallucinated
comparison. Additional evidence alongside Done Criteria, never a replacement, and bound by
the existing retry and circuit-breaker caps.

## Steps
- [ ] 1. Write `skills/anti-hallucination/references/bar-comparison.md`: the three-part bar test; the blind protocol (the critic sees the artifact only, never the builder's report, so it cannot know how hard the builder tried); binary verdict only, since a 1-10 score drifts upward every round; who may declare a bar; and the explicit statement that this is additive evidence still bound by `max_retries` and the two circuit breakers. The reference lives under anti-hallucination because Fetchable IS that skill's rule applied to comparison targets. (needs: -)
- [ ] 2. Name the new reference in `skills/anti-hallucination/SKILL.md` so `validate-no-orphans.sh` resolves it. (needs: 1)
- [ ] 3. Write `scripts/check-bar.sh` validating a bar envelope (`bar:` / `source:` / `compare:`): reject a vague category label from a denylist (award-winning, best-in-class, industry-leading, modern, professional, top-tier); require `source:` to resolve as a local path or parse as an http(s) URL; require a non-empty `compare:`. The header must state plainly that URL REACHABILITY IS NOT VERIFIED, because the plugin makes no network calls -- claiming a full Fetchable check would be the overclaim this gate exists to prevent. (needs: 1)
- [ ] 4. Add regression tests to `scripts/ci/test-scripts.sh`: a named bar with a resolvable local source passes; "award-winning SaaS sites" is rejected as a category; a source pointing at a nonexistent path is rejected; an empty `compare:` is rejected. (needs: 3)
- [ ] 5. Point `qa-engineer.md` at the reference as an optional evidence type, in 25 words or fewer. (needs: 1)
- [ ] 6. Give the mechanism a producer: `ui-ux-designer` AUDIT and REDESIGN may declare a bar envelope, in 15 words or fewer. A consumer with no producer is the exact defect this repo already shipped once in the memory vault, and it must not be repeated here. (needs: 1)
- [ ] 7. Run `run-all.sh`, confirm `validate-token-budget` still passes, and add the CHANGELOG entry. (needs: 2, 4, 5, 6)

## Files Touched
plugins/sefi-core/skills/anti-hallucination/references/bar-comparison.md; plugins/sefi-core/skills/anti-hallucination/SKILL.md; plugins/sefi-core/scripts/check-bar.sh; plugins/sefi-core/scripts/ci/test-scripts.sh; plugins/sefi-core/agents/qa-engineer.md; plugins/sefi-core/agents/ui-ux-designer.md; CHANGELOG.md

## Requires Tools
git

## Risks
Agents sit at 8222 of 8320 words, so steps 5 and 6 have 98 words of headroom between them; exceeding it fails `validate-token-budget.sh`. Putting the rule in a reference file rather than the agents is what makes that fit, and follows the existing close-out.md and goal-intake.md pattern. `check-bar.sh` cannot verify a URL is reachable offline, so Fetchable is only partially enforced. Adopting the bar test must not drag in Gauntlet Loop's uncapped loop: the exit here stays PASS/REJECT under `max_retries`, never "until the critic is wowed".

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` passes including `validate-token-budget`, and `check-bar.sh` exits 0 on a named bar with a resolvable local source and nonzero on "award-winning SaaS sites".
