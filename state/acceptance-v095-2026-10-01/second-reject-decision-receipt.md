# Second-reject decision receipt (process mechanism)

A second QA REJECT on a slice blocks further dispatch on that slice until a
human decision receipt with all fields below exists. Completed decisions are
immutable and referenced by run receipts. This file uses the shipped
`inbox/` escalation mechanism, not a new gate architecture. A later decision
never retroactively authorizes an earlier retry.

## Required fields

| Field | Meaning |
|---|---|
| slice | Bounded slice identifier (loop path as recorded in `state/metrics.md`). |
| rejected commits | Commits (or evidence states) the two REJECT verdicts attach to. |
| cumulative count | Total REJECT count on the slice including this decision's basis. Never reset on resume. |
| human decision | Verbatim human reply plus confirm/change/exit selection. |
| decision time | Timestamp of the human reply with timezone. |
| authorized next bounded action | Exactly one additional bounded remediation + independent QA cycle, scoped to named findings. |
| owner | Responsible software-engineer for the authorized cycle; separate QA judges it. |
| budget basis | Fresh `budget-check.sh --scope dispatch` and `--scope daily` results or a new execution-specific override (exit 3 is CANNOT MEASURE, not authorization). |

## Consumed decision 1 (immutable)

- slice: `systems-audit-v0.9.5/hermes-skill-scanner-copyfix-qa`, extended to
  the outstanding scanner-documentation and Slice 1 findings.
- rejected commits: UNVERIFIED -- the decision record
  (`inbox/escalation-systems-audit-v0.9.5-2026-09-29.md`) cites QA report
  paths (`qa-hermes-skill-scanner-fix-retry1.md`, VERDICT: REJECT) and the
  interim Slice 1 rejection, not commit SHAs. No SHAs are invented here.
- cumulative count: 2 per the decision record's own statement ("requires
  escalation after the second QA REJECT on a slice"). Only the retry-1
  REJECT row (retries=1) is retained in `state/metrics.md`; the earlier
  verdict row is UNVERIFIED in the retained records. The count is not
  reset by this receipt.
- human decision: "Proceed" -- confirm one additional bounded remediation
  and independent QA cycle. Publication stayed gated on all required QA,
  security, whole-branch review, hosted CI, and public-install checks.
- decision time: 2026-09-29 (Asia/Dubai; consumed_at 2026-09-29T08:44:00+04:00).
- authorized next bounded action: one additional bounded remediation and
  independent QA cycle for the roster-resolver (1/17) and security-warning
  regression findings plus Slice 1 collision/cap/overflow scenarios.
- owner: responsible software-engineer per dispatch; independent QA verdict
  recorded the outcome (PASS at retries=2; Slice 1 revalidation PASS).
- budget basis: UNVERIFIED in the retained record -- no fresh budget-check
  output is attached to the consumed decision. Later acceptance dispatches
  must obtain their own basis; this decision grants none.

Record: `inbox/escalation-systems-audit-v0.9.5-2026-09-29.md` (status:
consumed). Referenced by `state/metrics.md` rows dated 2026-09-29
("escalation consumed by user for one additional bounded cycle",
re-QA PASS at retries=2, slice1-revalidation PASS at retries=4).

Scope limit: this decision authorized only the cycle above. It does not
authorize the 2026-09-27 Slice 1 retry-2/retry-3 sequence that preceded it
(recorded nonconformance; see `process-reconciliation.md` section 7).

## Current acceptance state (Steps 1-4)

Cumulative REJECT count across acceptance slices in
`state/acceptance-v095-2026-10-01/`: **0**. All 23 `commands.jsonl`
records read PASS; all 22 blinded scenario verdicts in
`model-evidence/evaluator-verdicts.md` read PASS (21) or DIFFERENCE-NOTED
with no unsafe output (S18). No second-reject block is active. If any
acceptance slice reaches a second REJECT, dispatch on that slice stops
until a new human decision receipt with all required fields is recorded
here; resuming without one, resetting the count, or silently switching
models after a harness-limit notice is forbidden.
