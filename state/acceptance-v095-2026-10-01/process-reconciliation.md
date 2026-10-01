# Process reconciliation: v0.9.5 Systems Audit (2026-10-01)

Retrospective reconciliation of the historical v0.9.5 process records. Every
claim below traces to an executed command in this task or a named record
listed in Sources. Anything not found in those records is marked UNVERIFIED
with the search boundary disclosed. No private session text is published.
A later permission cannot retroactively authorize an earlier retry.

## 1. Original slice ownership

The historical corrected plan
(`state/handover-v095-2026-10-01/original-plan.md`, lines 61-69) defines
three bounded implementation slices:

1. **Skill and report contract** -- method, routing references, report-root
   support, behavioral verification. Target: `plugins/sefi-core/skills/systems-audit/SKILL.md`.
2. **Harness installation and documentation** -- runtime support,
   install/upgrade coverage, inventories, READMEs, onboarding. Targets:
   `plugins/sefi-core/scripts/install-hermes.sh`, `install-codex.sh`,
   READMEs, adapter docs.
3. **Release preparation** -- version metadata, changelog, release notes,
   prepublication ledger entries. Target: `state/release-ledger.md`.

Each slice required one responsible software-engineer dispatch and a
separate QA verdict with rerun evidence (original-plan.md line 69). The
predecessor 0.9.4 plan (`state/plan-systems-auditor.md`) used the same
one-engineer-plus-separate-QA shape for its slices 4-6, and
`state/session-handoff-auditor-2026-09-25.md` records slices 1-3 as
QA-passed with slices 4-6 pending at that time.

Structural match between plan and record: `state/metrics.md` contains rows
for `systems-audit-v0.9.5/slice1` (SKILL.md), `systems-audit-v0.9.5/slice2`
(install-hermes.sh), `systems-audit-v0.9.5/slice3` (release-ledger.md), plus
`installer-security`, `installer-cli`, `installer-cli-security`,
`whole-branch`, and `hermes-skill-scanner-copyfix-qa` loops. Source/history
areas match those slices. Same-engineer identity across retries within a
slice cannot be independently established from the retained records:
UNVERIFIED (bounded session handoffs and corrections are summarized in the
audit report, but full run receipts and private QA reports are not present
in the permitted snapshots).

## 2. Dispatch gates

Required gates before each dispatch (original-plan.md lines 69, 84):

- `check-handoff.sh` validation.
- `budget-check.sh` against the **$0.15 per-dispatch / $2.00 daily** caps.
- Record routes and receipts.
- Escalate after the **second REJECT** on a slice.
- Whole-branch review and installer/project-root security review before
  publication.
- Because the daily budget check reported `CANNOT MEASURE` (exit 3),
  execution had to obtain genuine spend telemetry or a task-specific
  override before specialist dispatch; an assumed zero was forbidden.

Mechanisms shipped: `plugins/sefi-core/scripts/check-handoff.sh`,
`budget-check.sh`, `model-for.sh`, `check-route.sh`
(`check-route.py` reads the session rollout for Codex dispatches),
`record-run-receipt.sh`, and the `config/budget.yml` caps. No new gate
architecture is introduced by this reconciliation.

## 3. Routes

`state/metrics.md` carries a `route` column (post-dispatch
`check-route.sh` status). Every recorded v0.9.5 dispatch row reads `match`;
non-dispatch rows read `n/a`. No `mismatch` or `invalid` row exists in the
retained metrics. Completeness across every historical dispatch is not
independently enumerable from the tag snapshot: PARTIAL (session commands
and metrics show handoff checks and `match` routes for recorded work, but
per-dispatch run receipts for each attempt were not retained in the
permitted evidence).

## 4. Receipts

- Machine QA verdict rows: `state/metrics.md` (full table, 2026-08-18
  through 2026-09-29) is the retained receipt set.
- Historical publication authorization: found -- direct user message
  2026-09-27 11:23:32 to implement the corrected plan including its
  publication sequence, plus "Continue and complete it" continuations
  (audit-report.md publication matrix; evidence-index.md notes the private
  provenance was inspected locally and is excluded here).
- 2026-09-29 escalation decision: `inbox/escalation-systems-audit-v0.9.5-2026-09-29.md`,
  status consumed, user reply "Proceed".
- Handover preparation authorization and budget basis (2026-10-01):
  `state/handover-v095-2026-10-01/preparation-status.md` -- user authorized
  handover preparation/review/commit/publication with spend UNKNOWN; both
  budget checks exited 3 CANNOT MEASURE; no zero-spend assertion
  substituted; that task-specific override does not authorize later
  implementation dispatch.
- Per-dispatch spend/override receipts and full run receipts for every
  historical attempt: not present in the permitted records. UNVERIFIED
  (see Search boundary).

## 5. Spend and overrides

- Caps: $0.15/dispatch, $2.00/day (original-plan.md line 69; plan Step 1).
- One-time daily-cap waiver recorded in the historical execution plan; sampled
  commands show budget checks were run (audit-report.md process matrix).
  A direct, comprehensive spend/override receipt for every dispatch was not
  retained: UNVERIFIED completeness.
- `state/metrics.md` 2026-09-26 `systems-auditor-token-budget-fix` row notes
  "daily bypass $2.40/$2.00" -- a daily-cap bypass is recorded there as an
  observed fact, not as a fresh authorization by this task.
- Slice 2 PASS row (2026-09-28) leaves "model-backed invocation and public
  smoke PENDING"; slice1 final PASS (2026-09-27) leaves "placeholder scan
  PENDING". PENDING items were disclosed, not counted as proof.
- Handover preparation (2026-10-01) override: spend UNKNOWN, documented in
  preparation-status.md, scoped to handover preparation only.

## 6. QA reruns

From `state/metrics.md` (target-path | loop | verdict | retries):

- systems-auditor slice4 (memory-cross-memory.sh): REJECT 0, then PASS 1.
- systems-auditor slice5 (init.md): PASS 0.
- systems-auditor slice6 (validate-release-ledger.sh): REJECT 1, PASS 2.
- systems-auditor slice4 security re-QA (validate-audit-report.sh): PASS 2.
- systems-auditor-token-budget-fix: PASS 0.
- systems-auditor-ci-fixture: PASS 0.
- systems-audit-v0.9.5/slice1 (SKILL.md): REJECT 0, REJECT 1 ("stop after
  second REJECT"), REJECT 2 (reopened), PASS 3.
- systems-audit-v0.9.5/slice2 (install-hermes.sh): REJECT 0, PASS 1.
- systems-audit-v0.9.5/slice3 (release-ledger.md): PASS 0 (hosted CI and
  strict completion PENDING at that time).
- installer-security: REJECT 0, PASS 1.
- installer-cli: REJECT 2, PASS 3.
- installer-cli-security: PASS 2.
- whole-branch (README.md): REJECT 0, REJECT 1. No whole-branch PASS row
  exists in the retained metrics.
- hermes-skill-scanner-copyfix-qa: REJECT 1 ("escalation consumed by user
  for one additional bounded cycle"), PASS 2.
- slice1-revalidation-after-escalation: PASS 4.

Current-acceptance reruns (Steps 2-4, 2026-10-01):
`state/acceptance-v095-2026-10-01/commands.jsonl` records 23 command
executions, all verdict PASS (6 deterministic suites, host fetch, and
installation/validator legs). `model-evidence/evaluator-verdicts.md`
records 22 blinded scenario verdicts: 21 PASS, 1 DIFFERENCE-NOTED
(S18, no unsafe output). No acceptance REJECT occurred, so the
second-reject circuit was not triggered during Steps 1-4; cumulative
acceptance reject count is 0 (see
`second-reject-decision-receipt.md`).

## 7. Retry counts and escalation

- The two-REJECT circuit: the scanner remediation stopped after its second
  rejection and consumed `inbox/escalation-systems-audit-v0.9.5-2026-09-29.md`
  (user: "Proceed", 2026-09-29, one additional bounded remediation + QA
  cycle). The mechanism existed and was used there.
- Slice 1 nonconformance: metrics record REJECT at retries 0 and 1 with
  "stop after second REJECT", then a reopened REJECT at retry 2 and PASS at
  retry 3, both dated 2026-09-27 -- before the 2026-09-29 decision. No
  intervening human decision between those Slice 1 attempts was recovered
  in the bounded review. RECORDED NONCONFORMANCE; any intervening private
  override is UNVERIFIED. The 2026-09-29 decision authorizes only the later
  scanner/Slice-1-findings cycle; it does not retroactively authorize the
  2026-09-27 retry-2/retry-3 sequence.
- Open escalation: `inbox/escalation-validate-release-ledger-2026-09-30.md`
  (red validator over historical lag rows). A superseding correction/status
  note is appended by Step 5 recording that replay at `153a729` passes both
  modes; the original contents are preserved as history.

## 8. UNVERIFIED items and search boundary

UNVERIFIED (not asserted absent, not asserted present):

1. Same-engineer identity across retries within each historical slice.
2. Independence of each historical QA rerun (binary outcomes retained;
   private QA report artifacts unavailable).
3. Per-dispatch spend telemetry and task-specific overrides for every
   historical dispatch (completeness).
4. Any intervening human decision between Slice 1 retry-1 and retry-2 on
   2026-09-27.
5. Final whole-branch PASS and post-final-commit security verdict on the
   exact release commit (metrics show whole-branch REJECT 0/1, no PASS).

Search boundary (records actually inspected; contents beyond these were
not used):

- This worktree: `state/metrics.md`; `state/plan-systems-auditor.md`;
  `state/session-handoff-auditor-2026-09-25.md`;
  `state/handover-ci-fixes-2026-10-01.md`;
  `state/handover-v095-2026-10-01/{original-plan.md,audit-report.md,evidence-index.md,preparation-status.md,audit-evidence/*}`;
  `state/acceptance-v095-2026-10-01/{README.md,baseline.md,commands.jsonl,model-evidence/evaluator-verdicts.md}`;
  `inbox/{approval-systems-auditor-v0.9.4-2026-09-27.md,escalation-systems-audit-v0.9.5-2026-09-29.md,escalation-validate-release-ledger-2026-09-30.md}`;
  `state/release-ledger.md`.
- NOT read and not published: private session text and per-run logs under
  `D:/Projects/Sefi-Agents/.worktrees/logs/` (directory names listed only
  to establish existence) and any ignored production audits, memory, or
  credentials. The parent checkout `D:/Projects/Sefi-Agents/state/metrics.md`
  was compared by tail rows only: it is an older snapshot (ends at the
  2026-09-29 scanner REJECT) superseded by this worktree's `state/metrics.md`.

## Sources

- `state/handover-v095-2026-10-01/original-plan.md` (historical plan: 3
  slices, gates, caps, escalation rule).
- `state/metrics.md` (machine QA verdict/retry/route rows).
- `state/handover-v095-2026-10-01/audit-report.md` (process/publication
  matrices, nonconformance findings).
- `state/handover-v095-2026-10-01/audit-evidence/tag-metrics-extract.txt`
  (tag-state metrics corroboration).
- `state/handover-v095-2026-10-01/evidence-index.md` (authorization
  provenance summary, record boundary).
- `state/handover-v095-2026-10-01/preparation-status.md` (2026-10-01
  authorization and budget basis).
- `inbox/escalation-systems-audit-v0.9.5-2026-09-29.md` (consumed
  second-reject decision).
- `state/acceptance-v095-2026-10-01/commands.jsonl`,
  `model-evidence/evaluator-verdicts.md` (current-acceptance rerun evidence).
