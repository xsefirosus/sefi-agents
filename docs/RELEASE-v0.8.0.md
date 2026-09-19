# v0.8.0 Release Notes

v0.8.0 makes Sefi-Agents local-first for durable project context and adds evidence-backed
repository research workflows. It keeps the default installation free of hosted services,
paid model calls, vector databases, browser renderers, and new runtime dependencies.

## Memory Journalist

- Replaces Knowledge Manager with Memory Journalist.
- Writes one privacy-filtered structured note for each substantial work session.
- Adds `/sefi:close-session`, `/sefi:memory-search`, and `/sefi:memory-index`.
- Keeps Markdown notes authoritative and rebuilds indexes locally.
- Adds optional local cross-project memory, disabled by default.

## Onboarding and reliability

- Every supported installer tells users to run `/sefi:init` from each project root.
- Installers explain why automatic initialization is unsafe and cross-project memory is
  optional.
- Adds atomic journal writes, recovery, idempotent close requests, task receipts,
  continuation limits, and package-drift checks.

## Design and repository research

- Adds Codebase Cartographer for MAP, TRACE, IMPACT, DELTA, and VISUALIZE work.
- Adds Adoption Scout for evidence-based external repository assessment.
- Expands UI guidance with three-variant prototypes, accessible selection, motion review,
  mobile behavior, and optional local visual workbenches.

## Public history

This release removes repository-root runtime `memory/` paths from rewritten public Git
history while retaining the packaged memory templates. The rewrite cannot remove files from
independent forks, existing clones, caches, or downloaded archives.

Read [Memory Journalist](MEMORY-JOURNALIST.md), [Privacy](PRIVACY.md), and
[the migration guide](MIGRATION-v0.8.0.md) for operational details.
