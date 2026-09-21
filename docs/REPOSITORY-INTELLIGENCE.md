# Repository Intelligence

This guide is for contributors who need a current, evidence-backed view of a repository or
who substantially update user-facing documentation. It explains the local artifacts Sefi
uses to keep maps and documentation facts current.

## Map a repository

Run `/sefi:map-codebase MAP <target>` for an inventory, then use TRACE for a requested
execution path, IMPACT before a change, DELTA after a change, CONTEXT for a bounded handoff,
or VISUALIZE for an offline viewer. The command writes:

```text
state/codebase-map-<slug>.md
state/codebase-map-<slug>.json
```

The JSON map uses `sefi-codebase-map/v2`. It records source evidence, file content and
structural hashes, freshness, baseline relationship, a private worktree identifier,
relationships, unresolved references, dynamic boundaries, and likely affected tests.
Absolute local paths and source edits are never part of the output.

Git and `rg` provide the baseline. A repeated map compares its prior Git baseline and
inventory. It reuses unchanged topology, refreshes evidence for content-only changes, and
re-extracts structural or uncertain files. If a previously mapped symbol disappears without
evidence of a delete, move, rename, or replacement, the candidate stays under
`.sefi/cartographer/<slug>/` and the prior map remains authoritative.

## Use context safely

CONTEXT creates up to eight deterministic local packets under
`.sefi/cartographer/<slug>/`. The default budget is 24,000 estimated tokens. The estimate
is `ceiling(UTF-8 byte count / 2)`, so it is deliberately not a provider token count.
Files are classified as full, structural, directory-only, or excluded. Sefi records every
omission and returns PENDING when required evidence cannot fit.

The local viewer embeds its data, script, and styles in one file. It uses no server, remote
asset, tracker, or network request. Mermaid remains the portable fallback.

## Optional connectors

Graft and CodeGraph are optional enrichment sources only when a user or handoff names one.
Sefi checks the local tool and index before importing supported evidence, preserves the
connector provenance, and falls back to Git and `rg` when it cannot validate the result.
It never installs, initializes, starts, configures, or changes telemetry for either tool.

## Keep documentation facts current

Technical Writer creates Claim sidecars only for substantial current-state documentation it
manages. They are stored at:

```text
state/docs-claims/<repository-relative-document-path>.claims.json
state/docs-manifest.json
```

Claims use `sefi-doc-claims/v1`. Each material factual statement has stable monotonic ID,
source path and line range, LF-normalized selected-text hash, baseline, provenance,
confidence, verification time, and producing task ID. Existing documents without a Claim
sidecar remain valid. Plans, historical changelogs, release notes, casual edits, and private
memory notes do not receive one.

Before a managed document changes, Sefi checks every Claim. A Claim is current when its
evidence still matches, stale when the source text changed, or unresolved when the evidence
cannot safely be read. Each stale or unresolved Claim receives exactly one decision:
confirm, update, retract, or replace. The manifest updates only after the document, Claim
sidecar, links, anchors, source evidence, and secret filter all validate together.

For multi-page work, each page has an existing task receipt, a local snapshot, and a
page-level finalization step. Completed pages resume only while their relevant evidence and
snapshot remain valid. Sefi never commits, pushes, merges, or publishes documentation by
itself.

## Privacy and limits

Maps, packets, candidate diagnostics, Claim files, manifests, and viewers are scanned for
credential-shaped content before they are written. The scanner redacts safely isolated
values or fails closed when the finding is ambiguous. It reduces accidental exposure; it
cannot guarantee that every secret format is detected.

Markdown remains the documentation source of truth. Map caches, packets, viewer files,
preflight reports, snapshots, and candidate results are disposable local derivatives.
