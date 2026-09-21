# Documentation grounding

Load this reference only for substantial current-state repository documentation. It
implements Sefi's local, evidence-bounded documentation lifecycle. Markdown remains the
user-facing source of truth; Claim sidecars record only the factual statements that need
future re-verification.

## Scope and ownership

Technical Writer owns prose and Claim reconciliation. Codebase Cartographer owns the
source map, freshness, traces, and CONTEXT packet. QA owns the final evidence verdict.
Task receipts under `.sefi/runs/<session-id>/` remain the only continuation authority.
Release Tracking owns historical changelog and release-version truth. Never copy a full
code map or source excerpts into a Claim sidecar.

Create a Claim sidecar only when substantially creating or revising a current-state
README, installation or migration guide, adapter or command guide, architecture or
workflow guide, optional-tool guidance, or privacy guidance. Do not create one for a
typo or formatting-only edit, a plan or temporary state report, a Memory Journalist note,
a historical changelog entry, release notes, or user-owned files beyond the request.
Legacy documentation without a sidecar remains valid. Do not bulk-migrate it.

## Claim contract

The authoritative files are:

```text
state/docs-manifest.json
state/docs-claims/<repository-relative-document-path>.claims.json
```

The sidecar uses `sefi-doc-claims/v1` and contains `schema`, `document`,
`next_claim_number`, `verified_document_hash`, `verified_baseline`, and `claims`.
Every active Claim has a stable ID, one factual statement, one or more evidence records,
last verified baseline, verification time, and producing task ID. IDs are monotonic per
document: `<document-slug>-c0001`, then `<document-slug>-c0002`. Never renumber one.

An evidence record has a stable ID, repository-relative path, inclusive line range,
SHA-256 of the selected LF-normalized source text, Git baseline, origin, derivation,
confidence, and optional Cartographer map or node references. Allowed origins are
`git-rg`, `graft`, `codegraph`, `cartographer`, `direct-repo`, and `user-supplied`.
Allowed derivations are `observed`, `imported`, and `heuristic`.

Create Claims only for material current facts whose error could mislead installation,
configuration, operation, security, compatibility, architecture understanding, or feature
use. Exclude opinions, marketing, navigation text, writing advice, clearly historical
narration, and facts governed solely by the release ledger. Do not place credential-like
values, source excerpts, raw conversations, command dumps, or diffs in an artifact.

## Preflight and reconciliation

Before editing a managed document, load its Claim sidecar and manifest entry, verify the
document hash, resolve every source path and range, recalculate source hashes, and write a
local preflight report under `.sefi/docs/<run-id>/preflight.json`.

Classify each Claim as:

- `current`: every source exists and its selected text hash matches.
- `stale`: a source exists but the selected text changed.
- `unresolved`: source evidence is missing, unsafe, or cannot be checked.
- `document-drift`: the page differs from its last completion manifest.

Keep unaffected current Claims automatically. Each stale or unresolved Claim requires
exactly one decision: `confirm` re-verifies the same fact; `update` revises its statement
or evidence but retains the ID; `retract` removes matching prose and the active Claim;
`replace` retracts the old Claim and allocates a new one. Never confirm without current
evidence. Reject duplicate or unknown decisions, duplicate active statements with the same
evidence, retractions whose prose remains, unsupported evidence, or a material managed
page with no active Claims.

For multi-page work, make a local page plan with page purpose, audience, seed evidence,
related pages, and order. Snapshot each page and its sidecar before editing. Each page has
one existing task receipt. Resume completed pages only while their relevant evidence and
snapshot remain valid. Stop automatic recovery when a concurrent user edit differs from
the snapshot. A failed page is `needs-attention`; never update the authoritative manifest
from failed work.

Use `scripts/docs-grounding.py` for local Claim validation, preflight, atomic finalization,
and manifest validation. It uses no provider or network service.
