# Documentation finalization

Load this reference only after a substantial current-state documentation edit.

## Per-page gate

The page and Claim sidecar must become durable together through temporary files, flushes,
and atomic renames. Before publication, verify the document hash, Claim hash, every active
Claim's current source evidence, and the selected source baseline. A malformed sidecar,
missing source, changed source during writing, or manifest mismatch returns
`needs-attention` and preserves the last valid files.

The page completion manifest at `state/docs-manifest.json` uses `sefi-docs-manifest/v1`.
Each entry records the repository-relative document path, document SHA-256, Claim sidecar
path and hash, source baseline, producing task ID, validation result, and completion time.
It does not duplicate Claims or source excerpts.

## Whole-set gate

Before reporting success, validate:

1. Relative file links and heading anchors.
2. Referenced scripts and commands.
3. README agent, skill, and command counts.
4. Claim statements and document meaning.
5. Evidence freshness, page and Claim hashes, and manifest consistency.
6. Navigation references and source drift.
7. Credential-shaped content in all generated artifacts.

Report a broken link or fact with its file, line, target, and reason. Do not insert warning
comments into prose and do not regenerate documentation indexes automatically. Keep the
writing audience-first: explain responsibilities, entry points, flow, state, failure
behavior, configuration, security, operations, extension seams, and focused tests when
they matter to that page.

For a substantial multi-page task, run whole-set finalization and QA after every page gate
passes. Never automatically commit, push, publish, merge, or open a pull request.
