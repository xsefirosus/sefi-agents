# Bar Comparison -- an optional qa-engineer evidence type

Additive evidence only. Done Criteria (`state/plan-<slug>.md`) stays the qa-engineer's
primary stop condition on every slice; a bar comparison never replaces it, and only
applies when a real external artifact exists to compare against. `scripts/check-bar.sh`
gates the envelope below before a verdict may cite it.

## The bar test: Named / Fetchable / Comparable
A bar envelope has three required fields, and all three must pass before a verdict may
cite the comparison:
- **Named** (`bar:`) -- a specific real artifact, not a category. "Linear's issue list
  view" is Named; "award-winning SaaS sites" is not. `check-bar.sh` rejects a denylist of
  vague category labels (award-winning, best-in-class, industry-leading, modern,
  professional, top-tier) -- the same failure mode this skill's rule 5 already names for
  numbers: an unlabeled category reads as a fact.
- **Fetchable** (`source:`) -- a local path or an http(s) URL where the bar can actually be
  inspected. This IS this skill's core rule (verify-before-cite) applied to a comparison
  target: an artifact nobody can open cannot be compared against, only asserted about.
  `check-bar.sh` checks a local path for real; a URL's reachability is NOT verified, since
  the plugin makes no network calls -- stated plainly rather than overclaimed.
- **Comparable** (`compare:`) -- the specific dimension under comparison, named, not "it's
  better." "Keyboard-first triage speed" is Comparable; "it's better" is not.

## Blind protocol
The critic (qa-engineer) sees only the artifact and the bar -- never the builder's report,
rationale, or effort narrative. A stated rationale never downgrades a finding elsewhere in
this repo's qa-engineer.md; the same principle here means the critic cannot know, and must
not be told, how hard the build tried. Comparison against the bar only.

## Binary verdict only
The verdict is MEETS_BAR or DOES_NOT_MEET_BAR -- never a 1-10 score. A numeric score
drifts upward every round even when the underlying work does not improve: published
first-party data from a similar critic-loop technique (Matt Shumer's "Gauntlet Loop")
shows a score climbing 3.59 -> 5.05 out of 10 across repeated rounds while never once
crossing its own declared bar. A score that can rise without a verdict changing is
measuring the critic's fatigue, not the work.

## Who may declare a bar
`ui-ux-designer` AUDIT and REDESIGN only. A bar with no declared producer is the same
defect this repo already shipped once in the memory vault (a consumer with no producer);
this reference exists so that does not repeat here.

## Bound by the existing caps
A bar comparison is judged like any other qa-engineer finding: `max_retries` and both
circuit breakers (stagnation, no-progress) still apply. This explicitly does NOT adopt
Gauntlet Loop's own uncapped design ("loop until the critic is wowed," no default retry
limit) -- that conflicts with the retry and circuit-breaker caps that exist here because
of a documented predecessor incident (a self-batching dispatch that burned 1.36M tokens).
PASS/REJECT under the existing caps, never an open-ended loop toward a moving target.

Self-test: every bar-comparison claim in a verdict traces to a `check-bar.sh`-passed
envelope and a binary MEETS_BAR/DOES_NOT_MEET_BAR verdict -- never a score, and never a
bar the critic saw the builder's report before judging.
