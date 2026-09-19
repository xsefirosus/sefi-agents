---
description: Examine an external repository for evidence-backed adoption candidates without copying or implementing it.
managed-by: sefi-agents
---

# /sefi:scout

Route this command through `codebase-cartographer`, then `adoption-scout`, then
`product-manager`. Usage: `/sefi:scout <source>... [--plan <path>] [--visual]`.

The Adoption Scout inventories every non-`.git` file, fully reads textual source, tests,
prompts, schemas, configuration, and documentation, then hashes and classifies binary or
static assets without semantic claims. It examines entry points, normal and failure paths,
tests, CI, releases, licences, notices, and provenance.

Write evidence only to `state/adoption-<date>-<slug>.md`. Classify each candidate as
`Adopt`, `Defer`, or `Reject` using a demonstrated Sefi gap, source evidence, role
distinctness, privacy, dependency cost, provenance, reversibility, and measurable checks.
Never copy third-party material, add a dependency, edit the target repository, implement a
candidate, or edit a plan directly. The Product Manager alone may append accepted work to
the supplied plan.
