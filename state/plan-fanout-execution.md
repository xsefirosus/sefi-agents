## Objective
Execute the fan-out that `morning-triage.loop.md`, `engineering-manager.md` item 5, and
`budget.yml` all already declare. A deterministic script computes the ready set from a
plan's `(needs: ...)` markers, and the Handoff move dispatches up to
`max_parallel_worktrees` findings concurrently instead of one at a time. Nothing new is
imported; three existing declarations stop being prose.

## Steps
- [x] 1. Write `scripts/ready-steps.sh`. Parse `- [ ]` / `- [x]` steps plus `(needs: N,M)` and `(needs: -)`; emit the unchecked steps whose dependencies are all checked, capped at `max_parallel_worktrees` from `config/budget.yml`. Exit codes follow budget-check.sh's precedent: 0 ready set emitted, 1 malformed (a dep naming a nonexistent step), 2 usage, 3 BLOCKED (unchecked steps remain but none are ready -- a cycle), 4 COMPLETE (every step checked). A silent empty result would let a caller mistake a cycle for a finished plan. (needs: -)
- [x] 2. Add regression tests to `scripts/ci/test-scripts.sh`: a linear plan yields exactly step 1; checking step 1 releases step 2; three `(needs: -)` steps yield three; four independent steps cap at three; all-checked exits 4; a two-step cycle exits 3; a dep on a nonexistent step exits 1. (needs: 1)
- [x] 3. Replace `test-integration.sh` stage 3's `grep -c '(needs: -)'` stand-in with a real `ready-steps.sh` call asserting the exact ready set, so the integration suite exercises the scheduler rather than approximating it. (needs: 1)
- [x] 4. Rewrite `engineering-manager.md` protocol item 5 to RUN `scripts/ready-steps.sh` rather than reason about markers in prose. Keep the edit word-neutral against the 8320-word cap. (needs: 1)
- [x] 5. Update `loops/morning-triage.loop.md` and its template: Handoff names `ready-steps.sh` as the source of the dispatch set; Verification states one qa-engineer pass per finding, never batched. (needs: 1)
- [x] 6. Run `run-all.sh`, confirm green, and add the 0.3.1 CHANGELOG entry. (needs: 2, 3, 4, 5)

## Files Touched
plugins/sefi-core/scripts/ready-steps.sh; plugins/sefi-core/scripts/ci/test-scripts.sh; plugins/sefi-core/scripts/ci/test-integration.sh; plugins/sefi-core/agents/engineering-manager.md; loops/morning-triage.loop.md; plugins/sefi-core/templates/loops/morning-triage.loop.md; CHANGELOG.md

## Requires Tools
git, awk

## Risks
A harness with no subagent dispatch cannot honor a ready set larger than one. `harness-actions.md` already carries the rule -- execute the roster sequentially and state it explicitly rather than pretending parallelism exists -- so the script's output degrades to advisory there, unchanged. A dependency cycle in a hand-written plan currently passes unnoticed and will now exit 3; that is the intended change, but it turns a previously silent malformed plan into a hard stop. Batching qa-engineer passes to save tokens would dilute the task-scoped adversarial focus its own Role line depends on, so step 5 forbids it explicitly rather than leaving it to judgment.

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` passes with the new assertions, and `ready-steps.sh` emits exactly three step numbers for a plan with three `(needs: -)` steps and exactly three for a plan with four.
