## Objective
Add a deterministic placeholder/hallucination-pattern scanner as evidence the qa-engineer
judges, closing the detection half of a discipline the `anti-hallucination` skill only
covers on the writing side (prevention). 4 of the source proposal's 5 pattern categories
are portable as-is; `code_generation` is excluded, confirmed redundant with
`check-reply.sh`'s existing foreign-deliverable check (its check 3 already catches a full
HTML/plan-skeleton leak from a read-only agent -- the same failure shape the
`code_generation` patterns were trying to catch more crudely). Exit 0 always: this reports
evidence for a verdict, it does not issue one -- same relationship `check-bar.sh` has to
the qa-engineer's bar-comparison evidence type.

## Steps
- [ ] 1. Write `scripts/scan-placeholders.sh <file>` (or `-` for stdin), matching `check-bar.sh`'s house style (arg parsing, `err()` helper, `key: value`-free since this scans free text not an envelope). Four categories only: `uncertain_language` (I believe/think/assume/guess that; probably/likely/possibly/maybe works), `incomplete_implementation` (TODO: implement/add/fix/create; FIXME:; HACK:), `placeholder_content` (placeholder; lorem ipsum; xxx+/aaa+/zzz+; your_[a-z_]+_here), `test_urls` (http(s)://example.com|localhost|127.0.0.1). Reports machine-readable `CATEGORY: N hit(s)` lines on stderr, one per category with N>0, plus the matched lines for context. ALWAYS exits 0 -- this is evidence collection, not a verdict; a caller must read the hit lines, never treat a clean stderr as a pass/fail signal on its own. KNOWN PITFALL from the prior build attempt: a bash `case` pattern needs the space INSIDE the quotes (`*" maybe "*`), not outside (`*"maybe "*`) -- the stray-quote version is a shell syntax error, not a silent bug, so `bash -n` catches it immediately if hit again. (needs: -)
- [ ] 2. Write `skills/anti-hallucination/references/placeholder-scan.md`: what each category means, and explicit false-positive guidance per category -- e.g. "probably" inside a sentence explaining *why* something is uncertain (a legitimate hedge) vs. "probably" attached to a claim the output asserts as fact (the actual defect). States plainly: a hit is a prompt to look, not an automatic REJECT; the qa-engineer judges each hit against the plan's Done Criteria the same way it judges everything else. (needs: 1)
- [ ] 3. Add one line to `anti-hallucination/SKILL.md`'s `## References` section (currently lists only `bar-comparison.md`), same format: `references/placeholder-scan.md -- ...`, naming `scripts/scan-placeholders.sh`. (needs: 2)
- [ ] 4. Add qa-engineer.md Protocol item 12 (current protocol runs 1-11, item 11 is bar-comparison): run the scan on the diff/reply before verdict; a hit is evidence to weigh against Done Criteria, never an automatic REJECT on its own. Word budget is tight -- only ~73 words of headroom across all 14 agents combined right now (8887/8960) -- so this item must land in roughly 20-25 words, no more. (needs: 3)
- [ ] 5. Regression tests in `scripts/ci/test-scripts.sh`: a clean baseline reports zero hits in every category; one hit case per category (4); a case with multiple hits in one category counts correctly, not just detects presence; an empty-input case exits 0 with no hits. At least 6 assertions. Prove at least one via re-break/restore (qa-engineer's own item 6 rule: temporarily break the pattern, watch the assertion fail, then restore) rather than trusting the test passed by construction. (needs: 1)
- [ ] 6. CHANGELOG entry (0.3.9) and the README Proof section's test-count line (currently `test-scripts: OK (94 passed)`) updated to the new total. (needs: 4, 5)
- [ ] 7. Run `run-all.sh` in full; confirm `validate-token-budget.sh` still passes against the 8960 cap. (needs: 6)

## Files Touched
plugins/sefi-core/scripts/scan-placeholders.sh; plugins/sefi-core/skills/anti-hallucination/references/placeholder-scan.md; plugins/sefi-core/skills/anti-hallucination/SKILL.md; plugins/sefi-core/agents/qa-engineer.md; plugins/sefi-core/scripts/ci/test-scripts.sh; CHANGELOG.md; README.md

## Requires Tools
git

## Risks
Word budget is the binding constraint, not line count (`anti-hallucination/SKILL.md` is 56/300 lines, `qa-engineer.md` is 117/150 lines -- both have room; the 14-agent total word pool does not). If step 4's line does not fit in the remaining ~73 words, cut elsewhere in `qa-engineer.md` first rather than raising the cap -- this repo's own discipline throughout this whole audit has been "spend headroom, do not raise the cap." Second risk: `code_generation`'s exclusion is a point-in-time judgment against `check-reply.sh` as it exists today; if that script's foreign-deliverable check is ever narrowed, this exclusion should be re-verified, not assumed to still hold. Third: the always-exit-0 design is deliberate but easy to misuse -- a future caller piping this into a boolean gate would silently treat every scan as a pass; the script's own header must state this as loudly as `check-reply.sh`'s CANNOT-CHECK exit-3 distinction does for its own gate.

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` passes with the new assertions included, `scan-placeholders.sh` reports the correct per-category hit count on a fixture containing all 4 patterns, and at least one category's regression test is proven via re-break (temporarily disable the pattern, confirm the test fails, restore, confirm it passes again).
