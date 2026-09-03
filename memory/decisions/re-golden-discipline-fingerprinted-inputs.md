---
tags: [decision, testing, process]
type: process-rule
status: active
date-discovered: 2026-09-03
evidence: astral-adoption Phase 4 benchmark case fingerprints
scope: benchmarks
---

# Re-Golden Discipline: Fingerprinted Inputs Must Be Re-Pinned

## The Rule

When editing a fingerprinted input (a file that feeds into a hash computation, such as `case_fingerprint = sha256(cat <prompt> <acceptance_check>)`):

1. Recompute the hash by the documented recipe.
2. Update EVERY pin of the old hash in the codebase.
3. Run a repo-wide grep for the OLD hash to prove nothing else references it (no cascade).

Do this in the same commit as the content edit.

## Why It Matters

A fingerprint is a commitment that the input has not drifted. If you edit the input without re-pinning, either the hash becomes stale (a bug) or you pin a different input (a correctness issue). A cascade -- another test or case that silently inherits the old hash -- can hide the drift and cause later surprises.

## Evidence From Astral-Adoption Run

**Phase 4 benchmark**, three successful re-goldens:

- Dropped stale "the allowlist is advisory" text from benchmark prompts.
- Re-golden'd the affected `case_fingerprint`s: `e8cdb70f..`, `81629762..`, `3367dd21..`.
- Verified: each old hash was removed from `cases.json` and no grep found a stale reference elsewhere in the repo.

## Implementation Notes

- Document the recipe in a comment near the fingerprint definition (e.g., in `cases.json` header or `benchmarks/README.md`).
- Automate the grep as part of pre-commit or CI if possible.
- If a cascade IS found, include it in the same commit and document why it was safe to update.

Related: [[memory/decisions/mandatory-check-must-fail-explicit]]
