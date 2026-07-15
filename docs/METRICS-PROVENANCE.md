# METRICS PROVENANCE

Every number cited in this repo's docs is either first-party (measured from this exact
system's own runtime) or predecessor-cited (observed in the prior Python/FastAPI build,
honestly labeled as such). This ledger tracks which is which, and what would need to be
true to promote a predecessor-cited row to first-party. Never invent a first-party number
to fill a row early -- an unmet promotion condition stays predecessor-cited, per this
repo's own anti-hallucination convention.

| Claim | Current source | Where cited | Promotion condition |
|---|---|---|---|
| Free-model dispatch success ~45% | Predecessor | `docs/BUDGET.md` | 4+ weeks of `state/metrics.md` PASS-rate rows from a live free-model loop on this architecture |
| Single dispatch hit 1.36M tokens (self-batching) | Predecessor | `docs/BUDGET.md` | A measured per-dispatch token total from `state/metrics.md` on this system, run with the per-dispatch cap already in place (expected to never reproduce the incident, which is itself the evidence the cap works) |
| Parse-ladder rescue avoided ~324K tokens (JSON present, not at position 0) | Predecessor | `docs/BUDGET.md` | A logged instance where this system's parse ladder actually recovered a reply the first rung missed, with the token cost of the naive re-ask it avoided |
| Broken browser tool burned a 50-iteration retry budget | Predecessor | `docs/BUDGET.md` | A logged instance where this system's tool-verification-before-granting step actually caught a broken tool before a loop retried against it |
| 184 green tests, half the new modules unwired | Predecessor | `docs/ANTIPATTERNS.md` | A qa-engineer wired/delete-the-line finding on this system's own code, with a before/after count of tests vs. actually-reachable modules |

## Standing check

During the weekly-retro pass, consult this ledger. If accumulated `state/metrics.md` data
now satisfies a promotion condition, propose the doc update as a normal bounded retro edit
(subject to the qa-engineer's pre-commit effectiveness check). An unmet condition is left
as-is -- this ledger tracks the gap, it does not manufacture evidence to close it early.
