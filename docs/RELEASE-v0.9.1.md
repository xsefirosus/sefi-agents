# v0.9.1 Release Notes

v0.9.1 adds Evidence-Bounded Repository Intelligence. Codebase Cartographer can validate
and incrementally refresh source maps without presenting stale evidence as current.
Technical Writer can track material documentation Claims against current repository evidence.
The release remains local-first, offline-testable, and dependency-free.

## Repository maps

Maps now use `sefi-codebase-map/v2` with worktree and Git-baseline checks, structural
fingerprints, per-file freshness, symbol-loss protection, unresolved references, dynamic
boundaries, impact and delta separation, token-bounded context packets, secret filtering,
and an optional offline viewer. Graft and CodeGraph remain named-only local enrichment
tools; Sefi never installs or configures them.

## Grounded documentation

Substantial current-state documentation can use `sefi-doc-claims/v1` sidecars and a
completion manifest. Before a page changes, Sefi identifies current, stale, unresolved, and
document-drift conditions. Every stale or unresolved Claim needs an explicit confirm,
update, retract, or replace decision. Page work resumes through the existing task receipts.

## Release status

This working tree is prepared for v0.9.1. Local CI and fresh-install fixtures must pass
before a tag, GitHub release, or marketplace update is created. Publication requires
separate, explicit release authorization and evidence.
