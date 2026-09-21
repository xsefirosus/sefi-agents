# Migrating to v0.9.1

v0.9.1 adds evidence-bounded repository maps and documentation grounding without adding an
agent, skill, command, service, or required dependency. Sefi remains at 16 agents, 19
skills, and 12 commands.

## Keep existing maps

Existing v1 code maps remain readable. Sefi does not rewrite a user-owned map automatically.
Create a fresh map with `/sefi:map-codebase MAP <target>` when you want the v2 freshness,
baseline, structural-fingerprint, uncertainty, and context-packet fields.

## Keep existing documentation

Existing documentation remains valid without Claim sidecars. Technical Writer starts a
sidecar only when it substantially creates or revises a current-state document that it
manages. It does not bulk-migrate old documents or create Claims for release notes,
historical changelogs, plans, memory notes, or small formatting work.

## Review local artifacts

Runtime derivatives live under `.sefi/cartographer/` and `.sefi/docs/`; they can be safely
rebuilt. Authoritative supporting records are `state/codebase-map-<slug>.json`,
`state/docs-claims/`, and `state/docs-manifest.json`. Read
[Repository Intelligence](REPOSITORY-INTELLIGENCE.md) before deleting or manually changing
an authoritative record.
