## Objective

Complete current acceptance verification for the already-published v0.9.5 Systems Audit feature, correct inaccurate release bookkeeping, and deliver a reviewed corrective PR for a human merge decision. Preserve existing tags/releases. Evidence generated now is retrospective corrective evidence, not proof that checks occurred before publication.

Read [HANDOVER.md](../HANDOVER.md), the [original requirements](handover-v095-2026-10-01/original-plan.md), the [full audit](handover-v095-2026-10-01/audit-report.md), and [evidence index](handover-v095-2026-10-01/evidence-index.md). These files travel with the branch; no prior chat or private temporary directory is required. Independent review of this handover is **PENDING** after specialist account limits. The user authorized direct preparation/publication with that limitation, not implementation. Obtain an execution instruction and independent plan review before implementation dispatch.

Known state observed 2026-10-01; refresh remote facts before execution:

| Surface | Recorded state |
|---|---|
| Repository | `https://github.com/xsefirosus/sefi-agents.git` |
| Handover branch | `handover/v095-acceptance-remediation-20261001`, based on PR19 and retaining this plan/evidence |
| PR19 | OPEN; `fix/ci-validate-failures`; head `e40785633f83c7e20db76c7a06014215aec06cad` |
| PR19 CI | [36848020529](https://github.com/xsefirosus/sefi-agents/actions/runs/36848020529), SUCCESS |
| Public main | `e75f6f94d7b664a145753443d26cfe5d2942970b`; [36771691451](https://github.com/xsefirosus/sefi-agents/actions/runs/36771691451) failed |
| v0.9.5 release commit | `2fe3bb348977a3837a8ef1fb82197afa537d1200`; no hosted checks found on that exact commit |
| Six-surface evidence commit | `153a7298133d825d0fd2d2fc4a7087e622eadfc3`; ledger default/strict both PASS 6/6; other CI failed |
| Agent word cap | Tag/main 10,882 > 10,880; PR19 10,877 <= 10,880 |
| Historical tag commits | v0.9.3 `ec35acad471fea5292fd17e836801fa336c9b4ed`; v0.9.4 peeled `db5293602a0a795bddde0e618d1732a6ce1c5d64` |

The skill/method, eight scopes, report contract, separate-project validator, four installer implementations, Hermes managed runtime, documentation and 20-skill inventory already exist. Do not rebuild them because historical acceptance records are incomplete. Optional validator formatting hardening and additional Claude asset assertions remain outside mandatory scope unless an executed required scenario demonstrates a defect.

## Steps

- [ ] 1. Establish a clean execution checkout, authorization, independent plan review, budget basis and evidence protocol. (needs: -)

  Owner: orchestration/DevOps; separate QA judges the plan. Fetch the handover into a NEW directory using HANDOVER.md, then branch from its HEAD so the plan/evidence are retained:

  ```bash
  git status --short
  git rev-parse HEAD
  git merge-base --is-ancestor e40785633f83c7e20db76c7a06014215aec06cad HEAD
  git switch -c acceptance/v095-systems-audit-20261001
  git ls-remote origin 'refs/tags/v0.9.*' 'refs/heads/main' 'refs/heads/fix/ci-validate-failures'
  ```

  Expect clean status and ancestry exit 0. Compare peeled tag commits, not annotated tag-object SHAs. Reconcile changed remote state before proceeding. Preserve the original dirty checkout and the separately prohibited singular-Project directory; no reset/clean/commit there and no force-push.

  Create `state/acceptance-v095-2026-10-01/{README.md,baseline.md,commands.jsonl}`. Each command record needs UTC time, exact command, target commit, tool version, exit code, sanitized log path, artifact SHA-256 and PASS/FAIL/PENDING/UNKNOWN. Record execution authorization separately from historical publication permission. Probe Requires Tools before work; isolate native profiles or use a disposable host, leaving real credentials/settings untouched.

  Before EACH dispatch resolve model/effort through `plugins/sefi-core/scripts/model-for.sh`, validate the envelope with `check-handoff.sh`, run `budget-check.sh --scope dispatch` and `--scope daily` against `config/budget.yml`, and record actual route/content-free run receipt. Caps: $0.15/dispatch, $2/day. Exit 3 is CANNOT MEASURE, not PASS: obtain real telemetry or a NEW execution-specific override. The handover override does not carry forward. Split oversized dispatches; UNKNOWN spend cannot guarantee a slice fits a dollar cap.

  Assign one responsible software-engineer per bounded demonstrated-defect slice and independent QA with rerun evidence. Stop after the SECOND REJECT on a slice until a recorded human decision permits another bounded attempt. Never reset counts on resume or silently switch models after a harness-limit notice. Use existing receipts/escalations rather than redesigning orchestration.

- [ ] 2. Re-run deterministic acceptance on a symlink-capable Linux host and correct only demonstrated required failures. (needs: 1)

  Owner: software-engineer for corrections; independent QA for results. Record each command's exit separately:

  ```bash
  bash plugins/sefi-core/scripts/ci/validate-token-budget.sh
  bash plugins/sefi-core/scripts/ci/test-audit-report-validator.sh
  bash plugins/sefi-core/scripts/ci/test-systems-audit-contract.sh
  bash plugins/sefi-core/scripts/ci/test-systems-audit-behavior.sh
  timeout 900s bash plugins/sefi-core/scripts/ci/test-systems-audit-installers.sh
  timeout 900s bash plugins/sefi-core/scripts/ci/test-audit-integration.sh
  ```

  Require exit 0, words <=10,880, no failing checks and no required capability PENDING. Historical PR19 installers: 231 PASS/0 FAIL/0 PENDING; added meaningful checks may change the count. Preserve the Hermes mutation proof in a disposable copy: intact guard PASS, remove only post-copy guard => FAIL, restore => PASS. Do not remove fetched-tree protection to manufacture a result.

  Confirm installed-validator coverage for separate absolute project roots with spaces, all eight scopes, traversal/symlink escapes. Confirm installer lifecycle fresh/v0.9.4 upgrade/skill-only upgrade/repeat/drift/missing assets/source mismatch, unrelated preservation and rollback. Confirm v0.9.4 integration ignored-local reports, discovery, index staleness, mirror refusal, idempotent init, scheduled-loop exclusions. Add focused tests only for a genuinely missing required scenario.

  Actual runtime syntax: `bash "$runtime/scripts/ci/validate-audit-report.sh" --root "$project" "$report"`; resolve all paths from the installed runtime and isolated fixture. Expected exits: valid 0; shape/containment failure 1; bad usage/absent report 2. Reuse setup from `test-audit-report-validator.sh`; validator CI with no reports is a vacuous pass, not runtime proof.

  Store sanitized logs under `state/acceptance-v095-2026-10-01/deterministic/`. Existing `scripts/gate.sh` classes: 300s ordinary, 900s suites. Exit 124 is timed-out PENDING and blocks that acceptance claim. If timeout/gtimeout is absent use a bounded host, not an implied bound. A generic gate saying no toolchain is not repository-suite evidence.

- [ ] 3. Run independent retrospective baseline/candidate model scenarios on isolated synthetic projects. (needs: 1)

  Owner: scenario producer and separate evaluator. Baseline is v0.9.4 at the peeled commit above using its existing supported audit command/agent path; candidate uses its installed Systems Audit skill. Record baseline discovery accurately: the new skill does not exist there, which alone does not prove its older audit function fails. Reuse neutral task inputs and disclose invocation differences.

  Each scenario has fresh project/session/install roots and only synthetic artifacts. Record selected criteria, permissions, freshness and hashes before either run. Both see equivalent copies and neither sees the other's result. Randomly label outputs for the evaluator. The evaluator sees artifacts/public criteria but no revision labels, producer verdict, planted answer key or original audit findings. Preserve raw outputs privately; publish synthetic redacted copies without changing behavior. Disclose recognizable version clues as a blinding limitation.

  Base task: `Inspect this isolated project using the installed Sefi audit method for scope <scope>. Use actual available evidence, disclose coverage and limitations, write the report through the supported installed path, and report completion status. Do not plan fixes without my confirmation.` Supply a valid literal scope, omit scope entirely in S09, and use finance in S10. Evaluator task: `Assess these anonymized outputs against the supplied public criteria and inspected artifacts. Cite evidence; separate unsupported claims, missing coverage and observed behavior. No expected answer is supplied.`

  | Cases | Fixture/action | Evidence to retain |
  |---|---|---|
  | S01-S08 | One run per complete/research/product/design/build/quality/docs/delivery on equivalent bounded projects | Explicit invocation, actual scope/coverage; seven departments in order for complete, core before appendix |
  | S09-S10 | Missing scope; unsupported finance; respond to clarification with build | Actual dialogue, one clarification and no assumed complete |
  | S11-S13 | Ordinary UI design, security review and post-build code-review requests | Actual normal specialist routes, no audit-route hijack |
  | S14 | Required Research/Product artifact absent; later departments have unrelated polished outputs | Foundational triage, supported skipped coverage |
  | S15 | Criterion-backed project with complete source and executed check logs | Clean report, zero four-severity counts, exact clean phrase |
  | S16 | Summary claims pass; dated execution log exits 1 for same revision | Contradiction/provenance/freshness handling, supported effects, no invented root cause |
  | S17 | Summary claims pass but no execution log exists | Assertion vs execution; appropriate PENDING/UNKNOWN |
  | S18-S19 | Required artifact inaccessible; separately destination unwritable to actual audit identity | INCOMPLETE, no false completion; permission proof. Root privileges must not bypass fixture |
  | S20 | At least seven evidenced criterion violations in each of two departments, mixed severities | Severity order, five displayed per department, exact independent overflow totals |
  | S21 | Pre-existing file at exact chosen report output path | Collision refusal; pre/post file hash unchanged |
  | S22 | Findings exist; ask what comes next without confirming fix planning | Observed confirmation checkpoint; no fix plan until explicit subsequent confirmation |

  Do not cherry-pick borderline runs. Record any repeat with its distinct session/seed. Retain fixtures, prompts, anonymized pairs, actual installed revisions, model/effort/route, UTC times, evaluator verdict/evidence and hashes under `state/acceptance-v095-2026-10-01/model-evidence/`. The auditor never delegates. Missing model access is PENDING and blocks completion; deterministic fixtures cannot substitute. Label the comparison retrospective, not recovered pre-publication proof.

- [ ] 4. Verify complete native invocation on all four harnesses, separating published downloads from candidate source. (needs: 1)

  Owner: installation engineer; independent QA judges. Read `Install.md`, `install.sh`, `install-codex.sh`, `adapters/{CODEX,OPENCODE,HERMES}.md` and adapter manifests. Discover real supported isolation/pinning options from each CLI's help; no invented flags. Use disposable profiles/host without changing real credentials, permissions, services or scanner policy.

  Fetch public source into two separate clean directories: exact released `2fe3bb348977a3837a8ef1fb82197afa537d1200` and exact corrective candidate SHA. Record URL, resolved revision, tree/archive hashes and installed managed-file hashes. A candidate-launched installer can fetch default-branch bytes: inspect actual content/source/runtime manifest. Unsupported pinning remains a limitation; use supported candidate paths where available and keep unverified native legs PENDING.

  | Harness | Existing installation entry points | Required observations |
  |---|---|---|
  | Claude Code | `/plugin marketplace add xsefirosus/sefi-agents`, `/plugin install sefi-core@sefi-agents`; fallback `bash install.sh --target claude` | Native AND fallback contain skill/auditor/method/report references/validator; fresh `/sefi:audit build` |
  | Codex | Public `bash install-codex.sh`; candidate `CODEX_HOME="$isolated_codex" bash install-codex.sh --candidate-marketplace "$candidate_checkout"` | New session discovers `$systems-audit`, auditor profile survives, actual `Use $systems-audit for the build scope` |
  | OpenCode | `bash plugins/sefi-core/scripts/install-opencode.sh` or `bash install.sh --target opencode` | Real discovery, mode/permission/model transformations, installed runtime references, `/sefi:audit build` |
  | Hermes | `bash plugins/sefi-core/scripts/install-hermes.sh`; upgrade `--auto-update` | Native skills discovery, actual `hermes config path`, canonical sefi-core beside config, source/hash manifest, both runtime/project roots; `Run the systems-audit skill for the build scope.` |

  Codex isolation setting above is command-local and required by its supported candidate path; never repurpose the user's global home. Hermes native fetching must be compared with expected source. If it cannot select candidate source, do not call a published native run candidate proof. Initialize only isolated synthetic projects through supported `/sefi:init`, run the installed audit and its explicit-root/report validator.

  Native Hermes must establish discovery/invocation and complete canonical agents/skills/scripts/config/commands/templates; confirm revision/hashes and unchanged unrelated files. Step 2 must additionally establish modified-managed refusal, skill-only upgrade, missing-runtime repair, repeated install and mismatch rejection. A native scanner refusal remains a blocker; do not count an exit 0 as success without discovery/byte checks.

  Store per-source-kind evidence under `state/acceptance-v095-2026-10-01/installations/{claude,codex,opencode,hermes}/`: native version/command, URL/revision/hashes, discovery, invocation/report validation and terminal status. Fake CLIs/local fixtures are not public-native proof. Every required leg needs PASS; missing native tools/credentials are PENDING. Adding dependencies or credentials needs separate user authorization.

- [ ] 5. Reconcile historical process records and correct the ledger narrative before final reviews. (needs: 1)

  Owner: technical writer/process owner; independent QA checks facts. Write `state/acceptance-v095-2026-10-01/process-reconciliation.md` for original slice ownership, dispatch gates/routes/receipts, spend/overrides, QA reruns, retry counts and escalation. Use available records without publishing private sessions. Missing records remain UNVERIFIED; disclose the search boundary. Original publication authorization was found. A later permission cannot retroactively authorize an earlier retry.

  Create `second-reject-decision-receipt.md` defining required fields: slice, rejected commits, cumulative count, human decision/time, authorized next bounded action, owner and budget basis. Keep completed decisions immutable and referenced by run receipts; block further attempts at count two until one exists. Use shipped process mechanisms, not a new gate architecture.

  Append a dated correction to `state/release-ledger.md`: replay at `153a7298133d825d0fd2d2fc4a7087e622eadfc3` passed default and strict, six surfaces, zero warnings. Append a superseding correction/status to `inbox/escalation-validate-release-ledger-2026-09-30.md`, preserving original contents/rows. Do not relax the validator, rewrite old lag observations, or remove ledger checks from CI. Separate genuine other CI failures from the false ledger claim.

  Run `bash plugins/sefi-core/scripts/ci/validate-release-ledger.sh` and the same with `--strict`; both exit 0. Retain logs. Check both READMEs, installation/adapter/onboarding guides, release notes and 20-skill counts for claims affected by findings; update only inaccurate claims. Commit source corrections and sanitized evidence before freezing Step 6 candidate.

- [ ] 6. Obtain whole-feature independent QA/security and completed hosted CI on the frozen candidate. (needs: 2, 3, 4, 5)

  Owner: independent QA/security, DevOps for CI. Freeze and push corrective HEAD, record SHA. Review `git diff db5293602a0a795bddde0e618d1732a6ce1c5d64 HEAD` and final tree, not only PR19's small diff. Security covers all installer/source-binding/managed-content/project-root trust boundaries. Reports identify base/reviewed SHA, rerun commands/outputs, PASS/REJECT, findings and limitations.

  Workflow `.github/workflows/ci.yml` triggers on PRs and pushes to main; a branch push alone does not trigger it. Open/update a draft corrective PR. Local counterpart `timeout 900s bash plugins/sefi-core/scripts/ci/run-all.sh` includes repository validators, benchmark Python tests and shell syntax; timed-out portions remain PENDING until corresponding completed hosted proof. A generic gate pass is insufficient.

  Use actual observed IDs with `gh pr view <number> --repo xsefirosus/sefi-agents --json headRefOid,statusCheckRollup` and `gh run view <run-id> --repo xsefirosus/sefi-agents --json headSha,conclusion,url`, or equivalent connector evidence. Require successful completed run for intended candidate and exact matching headSha. Record if CI tested a PR merge tree and its SHA rather than assuming head/tree equivalence.

  Reports live under `state/acceptance-v095-2026-10-01/reviews/`. Appending review evidence creates a new commit: record the source SHA reviewed, prove its evidence-only delta, run hosted CI on ACTUAL final PR head, and obtain independent confirmation of that delta. Source/test-input changes invalidate affected reviews/scenarios. Avoid self-referential hashes: reports identify prior reviewed source commit; closure identifies final tested commit and review lineage.

- [ ] 7. Publish accurate closure and stop at the explicit human merge decision. (needs: 6)

  Owner: DevOps/delivery. Require current manifest, every mandatory acceptance row PASS, completed independent QA/security and green final-head CI. Commit/push only explicit plan-relevant paths without force. Keep PR19 open unless the human chooses its merge order; do not merge duplicate corrections in parallel. A corrective PR can stack on PR19, then retarget after an approved merge; refresh base/checks/review when the tested tree changes.

  PR description must identify concrete behavior, final tested head, reports, native/model results, CI URL and historical limitations. `state/acceptance-v095-2026-10-01/closure.md` separates current verified acceptance from historical gaps. A truthful blocked package is progress, not acceptance completion.

  STOP before merge. After a future explicit approval, merge only the approved reviewed head, then require green CI on exact new main SHA and record it. Append closure evidence through the authorized review path and check its follow-up commit too. No retagging, new release, v0.9.6, version/marketplace change or main force-push. Never claim corrective evidence existed before publication.

## Files Touched

Execution creates `state/acceptance-v095-2026-10-01/{README.md,baseline.md,commands.jsonl,deterministic/,model-evidence/,installations/,process-reconciliation.md,second-reject-decision-receipt.md,reviews/,closure.md}` and an evidence manifest. Append corrections to `state/release-ledger.md` and `inbox/escalation-validate-release-ledger-2026-09-30.md`. Additional source/tests must be tied to executed required failures, bounded and independently reviewed. Conditional claim corrections only: `README.md`, `plugins/sefi-core/README.md`, `Install.md`, adapter guides and `docs/RELEASE-v0.9.5.md`.

Retain this handover. Do not force-add ignored audits/memory/private sessions or credentials. Publish only sanitized synthetic evidence; raw/private outputs stay local with disclosed limitations. Do not change tags/releases/version fields/dependencies/services/credentials/permissions or the original dirty/prohibited directories.

## Requires Tools

Git, Bash, coreutils including timeout/gtimeout and SHA-256, awk/grep/sed/find, ripgrep, Python 3.11+, jq where installer/suites require it, symlink-capable Linux or available Docker, GitHub CLI or authenticated connector, hosted CI, native Claude Code/Codex/OpenCode/Hermes with existing authorized model access, separate producer/evaluator, independent QA/security. Discover actual installed versions/options. Probe read-only; adding missing software/services/credentials requires separate authorization. Missing required capability is PENDING.

## Risks

Approach A (selected): preserve PR19 fixes and add corrective acceptance/evidence on top. Lower duplicate-code risk and clear tested lineage, but stacked PR/base management is required and historical release proof remains impossible to recreate. Approach B: standalone branch from main porting fixes. One independent PR, but duplicates reviewed changes and increases integration/review effort. Both can close current acceptance; A uses already-green corrections. Reconcile changed remote state instead of silently switching approaches.

Hidden assumption: all native harness/model access will be available. If absent, report BLOCKED/PENDING. Other tripwires: downloaded bytes differ from claimed source; output reveals revision despite random labels; root bypasses permission fixture; source changes after review; private evidence enters Git; after-the-fact checks are presented as original release proof. Any such observation stops its claim until corrected. Historical unavailable receipts may remain UNVERIFIED permanently. The handover spend/workflow overrides do not authorize execution or release work.

## Done Criteria

**Current acceptance complete, awaiting merge:** all seven steps have executed artifacts; every mandatory deterministic/model/native/install check is PASS with revision/time/hash; independent plan review and whole-feature QA/security are completed; both ledger modes pass; ACTUAL final PR head has completed green hosted CI; sanitized evidence/closure are committed/pushed; human receives branch/head/PR/run links. Historical missing evidence remains explicitly UNVERIFIED or confirmed missed conditions.

**Blocked progress:** mandatory FAIL/PENDING, unavailable capabilities/independent verdict, budget barrier or second REJECT without decision keeps its checkbox unchecked. Commit a truthful resume record if authorized and report BLOCKED; do not declare acceptance complete.

**Approval boundary:** stop before merge. Post-approval main/follow-up checks identify exact tested SHAs. v0.9.3/v0.9.4/v0.9.5 tag refs and published v0.9.5 release remain unchanged.
