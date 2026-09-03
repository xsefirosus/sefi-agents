---
tags: [decision, security, testing]
type: design-rule
status: active
date-discovered: 2026-09-03
evidence: astral-adoption Phase 3 route parser, Phase 4 integrity_ok, Phase 4 --injection hardening
scope: all
---

# Mandatory Check Must Fail Explicit (Never Skip)

## The Rule

Every mandatory check's ABSENCE must be an explicit failure, never a skip or pass-on-missing.

When a check's input is missing or a verification cannot run:
- FAIL CLOSED (reject the record).
- Never default the field to pass / not-applicable / skip.
- A regression test must assert the FAILURE mode: removing the check code reddens >=1 test.

## Why It Matters

A skipped check treated as a pass opens a decoy-injection vector. An attacker or buggy input can omit the check's field entirely, and the verifier will not catch it.

## Evidence From Astral-Adoption Run

1. **Phase 3 route parser** (jq-free POSIX shell, 4 review rounds): 5 distinct fail-open shapes where a decoy session record could make a downgraded dispatch report `match`. Fixed only by switching to real `json.loads` + top-level-only dict access (`check-route.py`), where a missing/mismatched field is structurally an explicit failure.
2. **Phase 4 integrity verifier**: The scorer's filter is `r.get("integrity_ok") is True`, so a record that OMITS the key is excluded (fail-closed). But earlier attempts had the RUNNER defaulting the field to pass when a check could not run.
3. **Phase 4 `--` injection hardening**: The fix landed correctly but had NO test asserting the slot-1/2 case. A later refactor could silently reintroduce the fail-open with a fully green suite. Closed only by adding the slot-1/2 delete-the-line regression assertion.

## Implementation Notes

- Use explicit error types, not silence.
- If a field is optional in the schema, that is separate from a field being "checkable"; mark both clearly.
- Every mandatory check must have a wired regression test that verifies its FAILURE branch (not just the happy path).

Related: [[memory/decisions/re-golden-discipline-fingerprinted-inputs]]
