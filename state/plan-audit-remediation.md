## Objective
Close the eight findings from the 2026-08-23 full-repo audit, at the scope the owner
chose per finding. The audit's two Critical findings share one root cause: nothing in this
repo has ever run unattended on a schedule, so `state/metrics.md` holds 3 manual rows,
`state/retro-ledger.md` holds zero, and `inbox/` has never received an item. Every
"UNKNOWN" cost-profile cell and the entire self-improvement claim rest on that gap.

Owner decisions taken as given (asked and answered before implementation):
- Codex `approval_policy`: soften `never` -> `on-failure`.
- Cron: prepare the two missing workflow files AND enable all three schedules.
- OpenCode/Hermes caveats: into the README harness table's Notes column.
- `terse-mode`: leave entirely as-is (no default flip, no new prose).

Two facts surfaced while verifying, both left deliberately unchanged and stated here so a
later reader does not mistake them for oversights:
- `improvement.enabled: false` in `config/sefi.config.yml`, deliberately per
  `commands/init.md`'s own shared-install guardrail. weekly-retro will therefore write
  PROPOSALS to `state/retro-<date>.md`, not applied edits. Finding F2 ("retro has never
  applied an edit") is only partly closed by this plan: the ledger stops being empty, but
  a genuinely applied edit needs that flag flipped, which is a separate decision.
- A `schedule` trigger has no `inputs`, so `DRY_RUN: ${{ inputs.dry_run }}` resolves empty
  on every scheduled run. The dry-run default protects manual dispatch only; scheduled
  runs open real PRs from the first firing. This is the owner's accepted risk, not a bug
  to silently patch -- a dry scheduled run produces no qa-engineer verdict and therefore
  no `state/metrics.md` row, which would leave the Critical findings exactly as blocked as
  they are today.

## Steps
- [ ] 1. Soften Codex `approval_policy` from `never` to `on-failure`. (needs: -)
  `.codex/config.toml`. Rewrite the surrounding comment: it currently argues for `never`
  as the fix for unattended stalls, and that reasoning no longer matches the value. State
  the real trade-off instead -- routine work still runs unattended, a command that
  actually fails surfaces rather than passing silently on the one harness with no
  per-command deny list.
- [ ] 2. Add the OpenCode and Hermes enforcement caveats to the README harness table. (needs: -)
  Notes column, both rows. OpenCode: `config/model-map.yml` maps `high` and `mid` to the
  same `flexible` sentinel, so the qa-engineer judges on an identical model and
  generator/evaluator separation is instructions-only (`validate-model-map.sh` already
  emits this as a WARN; the README is where an install decision is actually made). Hermes:
  same model collapse, plus `disallowedTools` is not read by Hermes at all
  (`adapters/HERMES.md` section 4), so a read-only agent's tool restriction has no
  enforcement behind it. Keep both cells short -- the table is scanned, not read.
- [ ] 3. Extend `test-integration.sh` to exercise the cross-project memory mirror. (needs: -)
  The mirror (`resolve-shared-memory-path.sh`, `write-shared-memory-mirror.sh`, shipped
  0.3.25) has unit coverage in `test-scripts.sh` but never runs inside the full-cycle
  test, which is exactly the "written, not wired" state `qa-engineer.md` item 3 exists to
  reject. Add to the existing close_out stage: stub `systemd-detect-virt` to `none` and
  clear the ephemeral env markers so the non-ephemeral branch is reachable, then assert
  the mirror file lands under `<root>/<project-slug>/<harness>-<topic>-<stamp>.md` and
  that its content is the same privacy-filtered text the daily note received.
- [ ] 4. Extend `test-integration.sh` to cover the `sync` loop spec. (needs: 3)
  `morning-triage` and `weekly-retro` are both copied into the test project's `loops/` at
  stage 1; `sync` (shipped 0.3.27, renamed 0.3.28) is not, so `loop-readiness.sh` and the
  probe stage never see it. Copy it alongside the other two and assert it scores as
  readiness-eligible, matching the assertion `morning-triage` already gets.
- [ ] 5. Write `validate-comment-safety.sh` and wire it into `run-all.sh`. (needs: -)
  A literal `--` inside an XML/HTML comment body is illegal XML and silently breaks the
  entire document's parse -- live-hit during 0.3.27, where an em-dash in an SVG comment
  blanked the whole diagram and the `<img>` rendered empty with no error anywhere. This
  repo's house style uses `--` as its em-dash in essentially every doc comment, so the
  collision is systemic, not a one-off. Scan `*.svg` and any `*.html`; a `--` occurring
  inside a comment body (never counting the closing `-->`) is an error naming file:line.
- [ ] 6. Write `.github/workflows/retro.yml` for the weekly-retro loop. (needs: -)
  `loops/weekly-retro.loop.md` declares `cloud: cron 0 7 * * 1 via a workflow file` and no
  such file exists -- `validate-loops.sh`'s workflow-existence check only fires on a
  declared `.github/workflows/<name>` path, so a vaguely-worded declaration slipped it.
  Model on `triage.yml`: same concurrency group pattern, same probe-tools preflight, same
  budget-check step, same commit-to-branch-and-open-PR ending (never merge). Schedule
  enabled per the owner's decision.
- [ ] 7. Write `.github/workflows/sync.yml` for the sync loop. (needs: -)
  Same shape as step 6, cron `0 8 * * 1` per the loop spec's own Monday-08:00 declaration
  (deliberately offset an hour from weekly-retro so the two never contend for the worktree
  budget). Schedule enabled.
- [ ] 8. Uncomment the `morning-triage` schedule in `.github/workflows/triage.yml`. (needs: 6, 7)
  Replace the "MANUAL TRIGGER ONLY, deliberately" header comment, which will no longer be
  true, with an accurate one: what enabling it costs, that scheduled runs are not dry runs,
  and how to switch back off (re-comment two lines).
- [ ] 9. Point both weekly loop specs at their real workflow files. (needs: 6, 7)
  `loops/weekly-retro.loop.md` and `loops/sync.loop.md` (and both templates).
  Both currently say "via a workflow file" rather than naming one. Naming the real path is
  what arms `validate-loops.sh`'s existence check for them -- the same check that would
  have caught this gap earlier had the declaration been specific.
- [ ] 10. CHANGELOG entry and version bump to 0.3.29. (needs: 1, 2, 3, 4, 5, 8, 9)
  Name the audit as the source, each finding closed, and both deliberate non-changes
  (`improvement.enabled`, `terse-mode`) so a later reader does not re-litigate them.
- [ ] 11. Run `bash plugins/sefi-core/scripts/ci/run-all.sh` in full. (needs: 10)
  Paste the real tail into the final report, including updated `test-scripts` and
  `test-integration` counts. A run that was not executed is PENDING, never assumed.

## Files Touched
.codex/config.toml; README.md; plugins/sefi-core/scripts/ci/test-integration.sh;
plugins/sefi-core/scripts/ci/validate-comment-safety.sh (new);
plugins/sefi-core/scripts/ci/run-all.sh; .github/workflows/retro.yml (new);
.github/workflows/sync.yml (new); .github/workflows/triage.yml;
loops/weekly-retro.loop.md; loops/sync.loop.md;
plugins/sefi-core/templates/loops/weekly-retro.loop.md;
plugins/sefi-core/templates/loops/sync.loop.md; CHANGELOG.md;
.claude-plugin/marketplace.json; plugins/sefi-core/.claude-plugin/plugin.json

## Requires Tools
bash, git, awk, sed, grep, jq

## Risks
- Steps 6-8 arm real unattended spend against a live API key and open real PRs on
  machinery that has never completed a supervised scheduled cycle. This is the owner's
  explicit decision, made against a stated warning, and the guardrails that remain are the
  ones already in the tree: `config/budget.yml` caps, the never-auto-merge rule
  (`human-checkpoint.md`), per-workflow concurrency groups, and the `acting_on` collision
  lock. None of those has been exercised under a real schedule either.
- All three schedules land within two hours of each other on Mondays (06:00 / 07:00 /
  08:00 UTC). That is the documented Parallel Collision failure mode
  (`docs/LOOP-FAILURE-MODES.md`, S3) and its mitigation -- the `acting_on` lock -- has
  never run live. Monday is the day to watch if anything is going to collide.
- Every workflow fails immediately without `ANTHROPIC_API_KEY` in repo secrets. That is a
  loud, cheap failure rather than a silent one, but it is a prerequisite this plan cannot
  satisfy from inside the repo.
- Step 3 makes the integration test depend on stubbing `systemd-detect-virt`. If a future
  CI image lacks that binary entirely the stub still works (PATH injection), but the
  assertion is proving the mirror's non-ephemeral branch, not proving real-machine
  detection -- which cannot be proven from inside a container at all. State that limit in
  the assertion's own comment rather than implying broader coverage.
- No prior note in `memory/decisions/` constrains this plan (vault checked; it is empty).

## Done Criteria
`bash plugins/sefi-core/scripts/ci/run-all.sh` exits 0 with all validators passing,
`test-integration` count strictly higher than 30, and `validate-comment-safety` present in
the output. `validate-loops.sh` passes with both new workflow files existing at the paths
the two loop specs now name (proving step 9 armed the existence check rather than merely
reworded prose). `.github/workflows/` contains three workflow files with an uncommented
`schedule:` block each, verified by grep rather than assumed.
