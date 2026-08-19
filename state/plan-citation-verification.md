## Objective
Bring into this canonical repo the fix another live install (OpenCode, a separate session)
already built and verified locally: a `qa-engineer` verdict cited `gate.sh` lines 91-96 as
"verified" that pytest's exit 5 was an accepted, documented case -- the lines were real and
in-bounds, but said nothing of the sort. Nothing downstream caught it before it reached a
human. That session's fix (independent protocol edits to their own local copy) is the
proof-of-concept; this plan ports the same discipline into the source repo so every future
install gets it, not just their one checkout.

## Steps
- [x] 1. Write `scripts/check-citation.sh <reply-file>|-`. Extracts every `<path>:<line>` or
  `<path>:<start>-<end>` citation token from the input, resolves `<path>` against the repo
  root or `plugins/sefi-core/`, and flags a citation whose file does not exist OR whose line
  number/range exceeds the file's actual length. Explicitly does NOT verify that the cited
  lines say what is claimed -- that is semantic, not mechanical, and the header states this
  plainly: the real fabricated citation this plan responds to (`gate.sh:91-96`) was real and
  in-bounds and this script would not have caught it. It only catches the cruder, purely-
  mechanical half: an impossible citation. Exit 0 clean, 1 one or more impossible citations,
  2 usage error. (needs: -)
- [x] 2. `qa-engineer.md` Protocol item 13: re-read a cited `file:lines` range yourself
  before writing `verified against` -- an unread citation is fabricated evidence by
  definition, whether or not the lines happen to exist. Terse (budget: ~13 words against
  the ~35-word headroom across all 14 agents combined; confirmed via
  `validate-token-budget.sh` in step 5, not assumed). (needs: 1)
- [x] 3. `engineering-manager.md` Protocol item 7: run
  `${CLAUDE_PLUGIN_ROOT}/scripts/check-citation.sh` on a returned qa-engineer verdict before
  accepting it; a flagged (impossible) citation sends the reply back once, then to `inbox/`
  -- same redo-once-then-inbox shape `check-reply.sh` already uses, a new deterministic gate
  alongside it rather than a replacement. Terse (~17 words). (needs: 1)
- [x] 4. Regression tests in `scripts/ci/test-scripts.sh`: a citation to a nonexistent file
  is flagged; a citation whose line range exceeds the real file's length is flagged; a
  citation to a real, in-bounds file:line-range passes clean; a single-line citation
  (`path:NN`, not just `path:NN-NN`) is handled; the exact real-world case (a citation to
  real, in-bounds lines that do not semantically support the claim) is confirmed to NOT be
  caught by this script, with a comment stating why -- proving the honest scope limit is
  real, not just claimed. At least 5 assertions. (needs: 1)
- [x] 5. Wire `check-citation.sh` into `scripts/ci/run-all.sh`'s check that scripts/ parse
  (already generic via `validate-model-map.sh`'s script count) -- no new CI registration
  needed beyond the test-scripts.sh assertions in step 4. Run
  `plugins/sefi-core/scripts/ci/validate-token-budget.sh` explicitly to confirm the two
  terse protocol additions did not blow the agents' combined word cap. (needs: 2, 3, 4)
- [x] 6. CHANGELOG entry crediting the originating finding (a separate OpenCode session
  running this repo's own main caught the fabricated citation live, fixed it locally, and
  this plan ports the same fix into the canonical repo) and naming the honest scope limit
  from step 1. (needs: 5)
- [x] 7. Run `run-all.sh` in full. (needs: 6)

## Files Touched
plugins/sefi-core/scripts/check-citation.sh (new); plugins/sefi-core/agents/qa-engineer.md;
plugins/sefi-core/agents/engineering-manager.md; plugins/sefi-core/scripts/ci/test-scripts.sh;
CHANGELOG.md

## Requires Tools
bash, sed, grep, wc

## Risks
The token budget is nearly exhausted (35 words of headroom across all 14 agents combined,
confirmed via `validate-token-budget.sh` before drafting either protocol addition, not
assumed) -- both additions are written to be maximally terse and verified against the
actual script's word count, not hand-counted and trusted. If the combined addition does not
fit, the correct response is to cut further, not to raise the per-agent cap, which is a
deliberate project-wide constraint this plan has no standing to loosen unilaterally.
Second risk: this script can never fully solve the problem it responds to -- a citation
that is real, in-bounds, and still semantically wrong (the actual case that happened) is
undetectable by any mechanical check; the protocol items exist precisely because the gap
above the mechanical layer needs a judgment call, not a script, and this plan states that
honestly in both the script header and the CHANGELOG rather than overselling the fix.

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` passes with `validate-token-budget.sh`
green (agents still under their combined word cap) and the new `check-citation.sh`
regression assertions passing, including one assertion that explicitly proves a real,
in-bounds-but-semantically-wrong citation is NOT caught -- the honest limit, demonstrated,
not just asserted in a comment.
