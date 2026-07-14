# LOOP-FAILURE-MODES

Runtime incidents a scheduled loop can hit once it is actually running against a live
project -- distinct from `docs/ANTIPATTERNS.md`, which catalogs mistakes in how this repo
itself is built. Each entry: Symptom / Severity (S1 Annoying, S2 Harmful, S3 Critical) /
Causes / Mitigation (the mechanism already in this tree, or the one this batch adds).

## Infinite Fix Loop
- Symptom: the same finding gets re-attempted turn after turn without ever passing.
- Severity: S2 -- burns budget with nothing to show, but bounded by max_retries.
- Causes: a fix that doesn't address the root cause; a flaky test the qa-engineer can't
  pin down; a stagnation condition (identical error repeating) going undetected.
- Mitigation: the stagnation/no-progress split (`loop-engineering/SKILL.md`, qa-engineer
  item 9) plus max_retries in `config/budget.yml`; both escalate to `inbox/` rather than
  looping forever.

## Parallel Collision
- Symptom: two loops (or two findings in the same loop) touch the same target within
  minutes of each other, each unaware of the other, wasting tokens and risking a
  conflicting fix.
- Severity: S3 -- can land two contradictory changes on the same branch/PR.
- Causes: no cross-loop visibility into what another loop is currently acting on.
- Mitigation: the `acting_on` collision lock (`docs/LOOPS.md` Multi-loop coordination
  section).

## State Rot
- Symptom: a resumed loop trusts a stale claim in its own `state/*.md` (e.g. "gate
  passed") that git itself contradicts.
- Severity: S2 -- a resumed run acts on outdated information, not a live one.
- Causes: a run that updated the state file but didn't commit, or was interrupted between
  the two.
- Mitigation: git-reconciliation trust, already in `loop-engineering/SKILL.md`'s Hard
  rules ("a state/*.md claim that disagrees with git loses to git").

## Verifier Theater
- Symptom: a PASS verdict that never actually executed anything -- narration dressed as
  evidence.
- Severity: S3 -- the single failure this repo's qa-engineer protocol exists to prevent.
- Causes: an evaluator that trusts a self-report instead of re-running the check.
- Mitigation: the qa-engineer's evidence-pair rule and delete-the-line test
  (`qa-engineer.md` items 3 and 5); already load-bearing, not new.

## Escalation Failure
- Symptom: a loop keeps retrying (or silently skips) a finding that actually needed a
  human decision, instead of routing it to `inbox/`.
- Severity: S2 -- delays a decision rather than corrupting anything.
- Causes: no clarify-before-acting step, so an ambiguous finding gets guessed at instead
  of flagged.
- Mitigation: the goal-intake escalation rule
  (`skills/sefi-orchestration/references/goal-intake.md`) -- an unresolved ambiguity gets
  an `- [ ] OQ:` line and a needs-human mark, never a guess.

No mitigation here overrides the human checkpoint; see
`skills/sefi-orchestration/references/human-checkpoint.md`.
