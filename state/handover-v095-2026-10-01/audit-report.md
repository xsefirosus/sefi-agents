# Full original-plan conformance review

Snapshot reviewed 2026-10-01. This historical review is separate from the new handover plan's independent review, which remains PENDING. Selected logs are packaged; omitted raw sessions/full logs are not dependencies. See evidence-index.md for provenance and public replay links.

# VERDICT: REJECT

Scope: read-only conformance review of the user-approved corrected Systems Audit v0.9.5 plan, its implementation evidence, and its publication evidence. `SUPPORTED` means executed evidence directly covers the requirement; `PARTIAL` means source or deterministic fixture coverage exists but the required live/procedural proof does not; `UNVERIFIED` means the permitted evidence cannot establish whether a historical action occurred; `FAIL` means executed evidence contradicts the requirement. Later PR19 evidence is reported separately and is not used to retroactively certify the published tag.

1. **Critical — the required independent model-agent before/after behavioral acceptance was not demonstrated.**

   Reproduction evidence:

   - The released `plugins/sefi-core/scripts/ci/test-systems-audit-behavior.sh` identifies itself as deterministic contract coverage and says it validates report/routing inputs, not LLM dispatch behavior ([tag-behavior-extract.txt](audit-evidence/tag-behavior-extract.txt)).
   - Hosted PR17 run `36424905130` executed `test-audit-integration.sh`, `test-audit-report-validator.sh`, `test-systems-audit-contract.sh`, and `test-systems-audit-behavior.sh`; all passed ([pr17-ci-key-lines.txt](audit-evidence/pr17-ci-key-lines.txt)). Those scripts exercise fixtures/helpers and do not supply a blind evaluating model.
   - The historical coordinating-session messages explicitly kept model-backed fresh-session behavior `PENDING`; they report an isolated Codex install/profile parse but no authenticated model-backed invocation. The same record says public-source smoke remained `PENDING` (`historical authorization provenance described in evidence-index.md` summarizes the inspected local evidence boundary; private factual provenance was inspected locally; it is not included in this public handover).
   - `state/metrics.md` at the tag also says Slice 2 passed while “model-backed invocation and public smoke PENDING” ([tag-metrics-extract.txt](audit-evidence/tag-metrics-extract.txt)). No retained paired pre-skill/post-skill agent transcript, isolated output pair, or independent evaluation without an expected answer was found in the permitted source, GitHub evidence, or bounded relevant session messages. Historical private evidence outside those surfaces is therefore `UNVERIFIED`, not asserted absent.

   The deterministic implementation is substantial, but it cannot satisfy the plan’s explicit behavioral stop condition. Proposed fix: preserve an immutable pre-skill and post-skill model run for the same scenario set, with isolated artifacts, prompt/run IDs, exact installed revision, raw report outputs, and a separate evaluator that is not given expected answers. Exercise missing and unsupported scopes, contradictory evidence, missing execution evidence, incomplete audits, confirmation before remediation, and adjacent non-audit requests.

   | Original behavioral group | Actual evidence | Status |
   |---|---|---|
   | Explicit invocation, eight scopes, missing/unsupported scope, adjacent routes | Routing fixtures cover explicit audit plus UI/security/post-build routes; all eight scopes reach the installed validator. Missing/unsupported behavior is primarily contract/text assertion. No model interaction proves the single clarification. | PARTIAL |
   | Foundational triage, supported findings, clean reports, contradictions, missing execution evidence, incomplete audits | Source method defines provenance, contradictions, `PENDING`/`UNKNOWN`, supported findings, and incomplete status. Shell fixtures hand-write clean/incomplete reports. No live auditor evidence demonstrates judgment over contradictory or absent execution evidence. | PARTIAL |
   | Severity order, per-department cap five, exact overflow, collisions, confirmation before fix planning | Actual formatter/path helpers are executed for order/cap/overflow/collision. Confirmation remains a contract assertion rather than an observed model checkpoint. | PARTIAL |
   | Installed validator against separate project, spaces, traversal and symlink escape | Released tests execute an installed runtime copy, separate root with spaces, traversal refusal, and physical-containment fixtures. Historical raw Linux symlink report is private; hosted PR17 executes the dedicated validator suite. | SUPPORTED for deterministic validator behavior |
   | Fresh install, upgrade, repeat, modified files, missing runtime, source-revision mismatch | Installer fixtures execute the real install scripts against controlled local trees and cover these cases. The harness wraps Codex/Hermes discovery with controlled CLIs; an isolated native Codex install/profile was recorded, while model-backed invocation remained `PENDING`. | PARTIAL |
   | v0.9.4 ignored reports, discovery, index staleness, mirror refusal, idempotent init, scheduled-loop exclusions | `test-audit-integration.sh` exercises these and passed on PR17’s hosted run. No hosted run exists for the final tag after later changes. | SUPPORTED at PR17 head; final-candidate proof FAIL |

2. **Critical — the published tag was not the hosted-CI-tested candidate, and the first release-evidence commit is demonstrably red.**

   Reproduction evidence:

   - `gh run list --commit 2fe3bb348977a3837a8ef1fb82197afa537d1200` returns `[]` ([tag-run-list.json](audit-evidence/tag-run-list.json)). GitHub check-runs for the tag commit report `total_count: 0`, and combined commit status has `total_count: 0`/`pending` ([tag-check-runs.json](audit-evidence/tag-check-runs.json), [tag-status.json](audit-evidence/tag-status.json)).
   - PR17 run `36424905130` succeeded at `d54b75aef443c797819ebb0b9b74e492902f69e5`; PR18 run `36463494557` succeeded at `641ce6b03c2b5b806b6896c11fc371259f68d9e9` ([pr17-head-run-list.json](audit-evidence/pr17-head-run-list.json), [pr18-head-run-list.json](audit-evidence/pr18-head-run-list.json)). Neither is the released commit.
   - Nine commits follow PR18’s merge commit before and including the release merge, with installer, containment, routing, integration, fixture, and documentation changes ([post-pr18-to-tag-commits.txt](audit-evidence/post-pr18-to-tag-commits.txt)). Earlier green runs cannot cover those changes.
   - The follow-up six-surface evidence commit `153a7298133d825d0fd2d2fc4a7087e622eadfc3` has hosted run `36771550621`, conclusion `failure` ([runs-153.json](audit-evidence/runs-153.json)). Its log reports personal-path violations, aggregate token budget failure, the Hermes fetched-runtime symlink regression, a checkout line-ending regression, and terminal `CI: FAILED` ([ci-153-failed-key-lines.txt](audit-evidence/ci-153-failed-key-lines.txt)).
   - Current public `main` is `e75f6f94d7b664a145753443d26cfe5d2942970b`; its run `36771691451` also failed with the same class of failures ([current-main-runs.json](audit-evidence/current-main-runs.json), [current-main-ci-failed-key-lines.txt](audit-evidence/current-main-ci-failed-key-lines.txt)).
   - A fresh LF clone replay of `validate-token-budget.sh` exits 1 at both the release tag and current main: `10882` aggregate words exceeds the `10880` cap (`token-tag.log/.exit`, `token-main.log/.exit`). PR19 `e40785633f83c7e20db76c7a06014215aec06cad` exits 0 at `10877` (`token-pr19.log/.exit`) and has a green hosted run, but remains open and cannot certify the historical tag ([pr19-current.json](audit-evidence/pr19-current.json)).

   This violates the requirement for repository gates and completed hosted CI on the exact final candidate. Proposed fix: do not move `v0.9.5`. Keep PR19 as the correction path under human review; once merged, require green CI on the exact new main commit. If another release is approved later, tag only an exact commit with whole-branch QA, security review, and hosted CI already attached to that SHA.

3. **Important — final whole-branch and security acceptance evidence is UNVERIFIED/PARTIAL after the last trust-boundary changes.**

   Reproduction evidence:

   - The tag’s durable metrics contain whole-branch `REJECT` rows at retries 0 and 1 and no subsequent whole-branch `PASS` row ([tag-metrics-extract.txt](audit-evidence/tag-metrics-extract.txt)).
   - Installer security has an earlier `REJECT` then `PASS`, but the release branch later changed installer path containment, per-write containment, behavior fixtures, routing, and CI handling before `2fe3bb3` ([post-pr18-to-tag-commits.txt](audit-evidence/post-pr18-to-tag-commits.txt)). No post-final-commit security verdict is attached to the tag.
   - PR17 and PR18 have no GitHub reviews or review comments ([pr17.json](audit-evidence/pr17.json), [pr18.json](audit-evidence/pr18.json)). Their bodies claim independent QA/security outcomes, but claims are not execution artifacts. Private reports referenced by historical sessions were outside the permitted clean snapshots and are `UNVERIFIED`.
   - The exact released/post-release tree then failed hosted checks in the trust-boundary and repository-gate areas noted above.

   Proposed fix: review the exact immutable candidate diff after all implementation commits, retain independent whole-branch and installer/project-root security reports, identify the reviewed tree/commit in each report, and link the exact hosted run. A pass on an earlier commit must be invalidated when trust-boundary files change.

4. **Important — required public-download verification before tagging is only partially evidenced and cannot be tied to all four harnesses or the final release bytes.**

   Reproduction evidence:

   - Slice 2 metrics explicitly leave public smoke `PENDING` ([tag-metrics-extract.txt](audit-evidence/tag-metrics-extract.txt)).
   - PR18’s body says two public-install failures were found by downloading the merged candidate, and the historical session records a real Hermes public-source scan. This establishes some public-source testing, but the retained PR body is a claim and provides no raw four-harness download logs, downloaded revision/content hashes, or a pass on the later release commit ([pr18.json](audit-evidence/pr18.json)).
   - Eight release-branch commits plus the merge follow PR18. No artifact proves Claude, Codex, OpenCode, and Hermes each downloaded and verified the final `2fe3bb3` content before the tag was created.
   - The deterministic installer suite uses real repository installer scripts but controlled/fake CLI seams for parts of Codex/Hermes. It proves local installer behavior, not native public downloads ([tag-installer-extract.txt](audit-evidence/tag-installer-extract.txt)).

   Historical evidence outside the permitted surfaces is `UNVERIFIED`; this finding does not assert that no ad hoc download occurred. Proposed fix: for a future approved release, retain a pre-tag ledger containing URL, HTTP result, resolved commit/revision, downloaded hashes, native harness command, and terminal result for each of the four harnesses. When all six publication surfaces match, report the release as published and describe public-smoke acceptance evidence as incomplete rather than calling the surface state partially released.

5. **Important — the recorded Slice 1 retry sequence exceeds the two-REJECT circuit, while any intervening override is UNVERIFIED.**

   Reproduction evidence:

   - Slice 1 metrics record `REJECT` at retries 0 and 1 with “stop after second REJECT”, then a reopened `REJECT` at retry 2 and `PASS` at retry 3 ([tag-metrics-extract.txt](audit-evidence/tag-metrics-extract.txt)).
   - The committed human-decision record dated 2026-09-29 authorizes one additional bounded cycle for later scanner-documentation and Slice 1 findings, but the Slice 1 retry-2/retry-3 sequence was already recorded on 2026-09-27. The bounded session review did not recover an intervening human decision between those Slice 1 attempts; a decision in unavailable private evidence remains `UNVERIFIED`.
   - The same metrics show scanner remediation did stop and consume an escalation after its second rejection, so the required mechanism existed but was not consistently applied.

   Proposed fix: make the second rejection atomically block further dispatch until an immutable user decision receipt exists; include the target slice and authorized retry count. Do not use a later escalation to retroactively validate earlier retries.

6. **Important — the release-ledger rows reconcile correctly, but their accompanying narrative falsely reports validator failure.**

   Reproduction evidence and before/after pair:

   - At the release tag and prepublication/evidence commit `58d05fd09878865bf4b693a557765dec86787de7`, default validation exits 0 with `4/6` plus two warnings, while `--strict` exits 1 because git-tag and GitHub-release are unobserved (`ledger-tag-*`, `ledger-58d-*`). This is expected pre-completion behavior.
   - At final evidence commit `153a7298133d825d0fd2d2fc4a7087e622eadfc3`, both default and `--strict` exit 0 with `6/6 surfaces observed, 0 warning(s)` (`ledger-153-*`). Current main and PR19 also pass both modes (`ledger-main-*`, `ledger-pr19-*`).
   - The validator source hard-fails semantic contradictions for any version and adds strict rejection for latest unobserved/non-match surfaces; `--strict` does not switch off historical validation ([ledger-semantics.txt](audit-evidence/ledger-semantics.txt)).
   - Despite that executable result, ledger notes at the final evidence state say the validator “still exits 1” on two historical lag conflicts ([ledger-v095-context.txt](audit-evidence/ledger-v095-context.txt)). The statement is not a current executable fact at `153a729`; it conflicts with the exact source and ledger at that commit. Current main’s inbox escalation is based on the same claimed failure.

   The plan’s strict six-surface completion requirement is **SUPPORTED** at `153a729`; the defect is inaccurate bookkeeping prose, not a failed strict gate. Proposed fix, if the user authorizes a documentation change: append a dated correction that records the exact default and strict commands/results at `153a729`, preserving prior rows and notes as history. Close or supersede the false current escalation without rewriting old evidence.

## Reconciled implementation summary

This matrix distinguishes source presence from behavioral or procedural proof. It incorporates the separate implementation review and corrects its statement that dedicated contract/validator logs were not retained: PR17 hosted CI does retain terminal passes for both scripts, although only at PR17 head.

| Implementation requirement | Released/current source | Executed proof | Status |
|---|---|---|---|
| `systems-audit` skill links evidence method and anti-hallucination; description <=60 words and main file <=300 lines | Skill and linked references are present; measured description is 23 words and file is 28 lines. | PR17 hosted CI runs `test-systems-audit-contract.sh` to terminal OK. | CODE PRESENT / SUPPORTED at PR17 head |
| Auditor remains authoritative; department document is readable criteria record | `agents/systems-auditor.md` holds seven-department criteria; `docs/AUDIT-DEPARTMENTS.md` defers to it. | Contract/document checks pass at PR17 head. | CODE PRESENT / deterministic proof |
| Evidence method defines scope/root/revision, evidence provenance/freshness/contradictions, risk sampling, bounded checks, supported findings, separate remedies, coverage/limits | `references/evidence-method.md` contains all six requested steps and preserves `PENDING`/`UNKNOWN`. | No retained live auditor output demonstrates method judgment end to end. | CODE PRESENT / live behavior PENDING |
| Explicit audit intent and skill route; preserve UI/security/code-review routes | Routing table retains audit, UI, trust-boundary/security, and post-build review rows. | Hosted behavior fixtures match each route; no model-backed adjacent-request transcript is retained. | CODE PRESENT / PARTIAL proof |
| Exactly eight scopes; missing/unsupported scope asks one clarification | Skill, command, agent, and contract share the eight-value allowlist and clarification rule. | Installed-validator fixtures cover all eight; missing/unsupported interaction is text/fixture coverage, not a model conversation. | CODE PRESENT / PARTIAL proof |
| Department order, core-before-appendix, foundational Research/Product triage | Auditor source orders the departments and defines foundational triage/`SKIPPED-TRIAGE`. | No retained live audit transcript exercises contradictory or missing foundational evidence. | CODE PRESENT / live behavior PENDING |
| Critical/Major/Minor/Nice order, five displayed findings per department, exact overflow | Agent, report contract, and formatter implement the order/cap/overflow. | Behavior suite executes formatter order, independent per-department caps, and exact overflow. | CODE PRESENT / deterministic proof |
| Eight-heading report, local `audits/` path, clean phrase/counts, collision refusal, explicit confirmation before fix planning | Contract and agent source define all requested behavior. | Behavior/validator suites exercise headings, clean/incomplete reports, and collision refusal. Confirmation remains unobserved model behavior. | CODE PRESENT / PARTIAL proof |
| Validator accepts absolute audited root plus explicit report; preserves repository default/exits/scopes and physical containment | CLI/default, allowlist, traversal, and containment logic are present in `validate-audit-report.sh`. | PR17 hosted CI runs `test-audit-report-validator.sh` to terminal OK, including separate project/spaces and escape fixtures. | CODE PRESENT / SUPPORTED deterministic behavior |
| Claude native and fallback include skill, agent, references, validator/runtime | Plugin manifest and fallback copy full skills/agents/commands/scripts trees. | Installer fixture proves key Claude command/agent/skill paths; it does not individually assert both references and validator. | CODE PRESENT / PARTIAL assertion coverage |
| Codex native exposes documented skill and Systems Auditor profile in an isolated install | Codex adapter/install paths and profile generation are present. | Historical evidence records isolated native install/profile parsing; model-backed fresh session remained PENDING. | CODE PRESENT / PARTIAL proof |
| OpenCode preserves skill/runtime and agent/permission transforms | Installer and adapter implement model-map, permissions, mode split, and runtime copy. | Repository/installer fixtures execute transforms and installed skill/report contract. | CODE PRESENT / deterministic proof |
| Hermes native discovery plus config-relative canonical runtime, explicit roots, source identity/hashes, unrelated-file preservation, drift/refusal/update/repair | Installer/runtime code implements config-relative managed runtime, manifest hashes, revision binding, expected-source checks, stale retirement, and refusal paths. | Installer fixtures cover fresh/repeat/legacy upgrade, missing runtime, drift, mismatch, rollback, and symlink cases; exact released follow-up CI later finds a Hermes symlink regression. | CODE PRESENT / final-candidate proof FAIL |
| Fresh install, existing-release upgrade, repeat install, modified managed files, missing runtime, source-revision mismatch | Lifecycle branches and diagnostics are present across installers. | Controlled installer suite exercises them; native all-four public-download final-byte proof is UNVERIFIED. | CODE PRESENT / PARTIAL proof |
| Both READMEs, install/adapter/onboarding guidance, 20-skill inventory, role/scope/invocation/report location | README, plugin README, `Install.md`, and Claude/Codex/OpenCode/Hermes adapter docs contain the guidance and inventory. | PR17 doc/count checks pass; PR19 later passes counts and documentation checks. | CODE PRESENT / supported documentation |
| Ignored-local audit reports participate in local discovery/index/staleness, stay outside mirror, and remain excluded from scheduled loops | Memory/init/loop integration points and docs are present. | PR17 hosted `test-audit-integration.sh` reaches terminal OK. | CODE PRESENT / SUPPORTED at PR17 head |
| Official ISO 19011, NIST SP 800-53A, IIA, and GAO adaptations with no certification claim | Evidence method links the four primary sources and explicitly disclaims certification/conformance. | Static source verification; no certification claim found. | CODE PRESENT / SUPPORTED |
| Aggregate agent budget | Tag/current main contain 10882 words against the 10880 cap; PR19 trims to 10877. | Fresh LF replay: tag/main exit 1; PR19 exit 0. | FAIL release/main; corrected in open PR19 |

Optional hardening, not a missed plan criterion: enforce exactly-once heading order/fenced-body/clean-sentence invariants in the validator, and add explicit Claude assertions for both references plus the validator. The plan required the report behavior and preservation of existing severity validation; it did not require every prose invariant to become a validator rule.
## Original implementation/process matrix

| Requirement | Evidence | Status |
|---|---|---|
| Three bounded slices: method/routing/report root/behavior; harness/install/docs; release prep | Metrics contain Slice 1, Slice 2, Slice 3 rows and the source/history matches those areas. | SUPPORTED structurally |
| One responsible software-engineer dispatch per slice | Bounded session records handoffs and corrections, but full run receipts/private reports are not present in the clean release snapshot. Same-engineer identity across retries cannot be independently established. | UNVERIFIED |
| Separate QA rerun per slice | Metrics and session summaries record binary QA outcomes; some hosted tests can be replayed from PR17 logs. Original private QA report artifacts are not available in permitted snapshots. | PARTIAL / UNVERIFIED independence |
| Handoff gate before dispatch; route receipts | Session commands and metrics show handoff checks and route=`match` for recorded work. Completeness across every dispatch is not independently enumerable from the tag. | PARTIAL |
| `$0.15` dispatch / `$2.00` daily; genuine telemetry or task-specific override because baseline was `CANNOT MEASURE` | The historical execution plan records a one-time daily-cap waiver and mandatory per-dispatch checks, and sampled commands show budget checks. A direct, comprehensive spend/override receipt for every dispatch was not retained in the clean evidence. | UNVERIFIED completeness |
| Escalate after second REJECT | Scanner remediation used escalation; Slice 1 records retries 2/3 after the two-REJECT stop marker. An intervening private override is UNVERIFIED. | RECORDED NONCONFORMANCE; override UNVERIFIED |
| Whole-branch and security review before publication | Earlier reports/claims exist, but no final-commit PASS is preserved in the permitted evidence and the released tree later fails relevant hosted gates. | UNVERIFIED / PARTIAL |
| Targeted regressions, repository gates, hosted CI on final candidate | PR17/PR18 hosted runs pass earlier heads; exact tag has zero checks; evidence commit CI fails. | FAIL |
| Local timeout/stall remains `PENDING`; completed hosted counterpart required | Metrics keep model/public/Windows portions `PENDING`, but no completed hosted counterpart exists on final tag. | PARTIAL / FAIL final-candidate condition |

## Publication/release matrix

| Publication requirement | Evidence | Status |
|---|---|---|
| PR17 full-feature title/body and README reuse | PR17 title is `feat(audit): ship systems-audit across four harnesses for v0.9.5`; body and history cover the feature and reused README work. | SUPPORTED |
| Four tracked version fields at 0.9.5; no invented Codex marketplace version | Tag snapshot has Claude plugin 0.9.5, Codex plugin 0.9.5, marketplace metadata 0.9.5, and marketplace plugin entry 0.9.5 ([tag-version-fields.json](audit-evidence/tag-version-fields.json)). No extra Codex marketplace version field was found. | SUPPORTED |
| Dated changelog/release notes | Tag has `[0.9.5] - 2026-09-28` and `docs/RELEASE-v0.9.5.md`. | SUPPORTED |
| Explicit user publication authorization | Direct user message at 2026-09-27 11:23:32 asked to implement the corrected plan, whose publication section authorizes merge, public verification, tag, release, and evidence push; subsequent messages said “Continue and complete it.” Private-session provenance is summarized in `historical authorization provenance described in evidence-index.md`. | SUPPORTED |
| Merge after QA/review/CI; exact tested release commit | Merge/tag commit is identifiable and user authorization is found. The exact tag has no hosted checks, later release-evidence CI fails, and post-final whole-branch/security proof is unavailable. | FAIL exact-tag CI; reviews UNVERIFIED |
| Actual public-download revision/content verification before tag | Partial public-source testing is claimed, but all-four exact-final-byte proof is not retained. | UNVERIFIED / PARTIAL |
| Annotated v0.9.5 tag at tested release commit | Annotated remote tag peels to `2fe3bb348977a3837a8ef1fb82197afa537d1200` ([tag-object.txt](audit-evidence/tag-object.txt), [remote-tags.txt](audit-evidence/remote-tags.txt)). It matches the GitHub release’s tag but was not an exact tested hosted-CI commit. | PARTIAL |
| Direct six-surface observations and strict final ledger | Final rows record all six; replay at `153a729` passes default and strict 6/6. The narrative failure claim is inaccurate. | SUPPORTED execution; Important documentation defect |
| Follow-up evidence commit pushed to main; tag remains original | `153a729` is in current main history; tag still peels to `2fe3bb3`. | SUPPORTED |
| Release URL/commit/public smokes/limits; partial if mismatch | Published release is https://github.com/xsefirosus/sefi-agents/releases/tag/v0.9.5, non-draft/non-prerelease, published 2026-09-30T20:15:59Z ([release-v0.9.5.json](audit-evidence/release-v0.9.5.json)). All six publication surfaces match, so “partially released” is not required by the surface rule. Acceptance evidence remains incomplete because final-CI and all-four public-smoke proof are unresolved. | SUPPORTED surface state; incomplete acceptance proof |
| Prior tags immutable; no v0.9.6 | Remote v0.9.3/v0.9.4 refs match recorded baselines; v0.9.5 remains at its original commit; no v0.9.6 tag or release appears ([remote-tags.txt](audit-evidence/remote-tags.txt), [release-list.txt](audit-evidence/release-list.txt)). Protection configuration itself was not queried. | SUPPORTED observed immutability; protection UNKNOWN |

## Current state, kept separate from historical conformance

- Public `main`: `e75f6f94d7b664a145753443d26cfe5d2942970b`; ledger default/strict pass 6/6, token budget fails 10882/10880, and hosted CI run `36771691451` failed.
- PR19: `e40785633f83c7e20db76c7a06014215aec06cad`, OPEN, mergeable/CLEAN, hosted run `36848020529` SUCCESS, token budget 10877, and later independent follow-up QA evidence is green. It awaits human review/merge and cannot retroactively certify v0.9.5.
- Release/tag: `v0.9.5` remains published at `2fe3bb348977a3837a8ef1fb82197afa537d1200`; no v0.9.6 exists.

## Evidence inventory and command results

- GitHub: [pr17.json](audit-evidence/pr17.json), [pr18.json](audit-evidence/pr18.json), [pr19-current.json](audit-evidence/pr19-current.json), [pr17-head-run-list.json](audit-evidence/pr17-head-run-list.json), [pr18-head-run-list.json](audit-evidence/pr18-head-run-list.json), [tag-run-list.json](audit-evidence/tag-run-list.json), [tag-check-runs.json](audit-evidence/tag-check-runs.json), [tag-status.json](audit-evidence/tag-status.json), [runs-153.json](audit-evidence/runs-153.json), [current-main-runs.json](audit-evidence/current-main-runs.json), [release-v0.9.5.json](audit-evidence/release-v0.9.5.json), [release-list.txt](audit-evidence/release-list.txt).
- Hosted logs: retained hosted key-line extracts; full logs can be fetched from the public run links in evidence-index.md.
- Release identity: [tag-object.txt](audit-evidence/tag-object.txt), [remote-tags.txt](audit-evidence/remote-tags.txt), [tag-version-fields.json](audit-evidence/tag-version-fields.json), [public-marketplace-main.json](audit-evidence/public-marketplace-main.json), [post-pr18-to-tag-commits.txt](audit-evidence/post-pr18-to-tag-commits.txt).
- Ledger replay in a clean disposable LF clone: `ledger-{153,main,pr19}-{default,strict}.{log,exit}` in the selected package; tag/58d replays described in the original review. Exact outcomes: tag/58d default 0 and strict 1 at 4/6 (historical review result; those replays are not included here); 153/main/PR19 default 0 and strict 0 at 6/6 (included).
- Token replay in a clean disposable LF clone: `token-tag.exit=1`, `token-main.exit=1`, `token-pr19.exit=0`, with full logs.
- Released source/metrics extracts: [tag-behavior-extract.txt](audit-evidence/tag-behavior-extract.txt), [tag-installer-extract.txt](audit-evidence/tag-installer-extract.txt), [tag-metrics-extract.txt](audit-evidence/tag-metrics-extract.txt), [ledger-semantics.txt](audit-evidence/ledger-semantics.txt), [ledger-v095-context.txt](audit-evidence/ledger-v095-context.txt).
- Authorization provenance: `historical authorization provenance described in evidence-index.md`; no hidden reasoning or credentials were copied.
