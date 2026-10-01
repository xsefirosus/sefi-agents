# v0.9.5 acceptance-remediation handover

Prepared 2026-10-01. This branch contains PR19's candidate plus the plan, original requirements, full audit and selected evidence. No new implementation fixes. Independent review of this handover is **PENDING** after specialist account limits; the user explicitly authorized direct completion/publication with that limitation.

Remote delivery is currently **BLOCKED**: terminal GitHub networking is restricted, and the authenticated connector rejected its write because this session's approval policy is never. The package is prepared for a local commit; publish this branch from an authorized environment before using the remote clone commands below. Do not assume the remote branch exists from this document alone.

## Fetch into a clean directory

```bash
git clone --branch handover/v095-acceptance-remediation-20261001 https://github.com/xsefirosus/sefi-agents.git sefi-v095-handover
cd sefi-v095-handover
git status --short
git rev-parse HEAD
git merge-base --is-ancestor e40785633f83c7e20db76c7a06014215aec06cad HEAD
```

Expect clean status and ancestry exit 0. Record fetched handover HEAD, newer than PR19 base above. Do not checkout the old PR19 head and lose handover files. Existing clean clone: `git fetch origin`, then `git switch --track origin/handover/v095-acceptance-remediation-20261001`. If the branch exists, compare histories before switching/updating. Never reset a dirty checkout.

## Copy-paste receiving prompt

> Read HANDOVER.md, state/plan-v095-acceptance-remediation-2026-10-01.md, state/handover-v095-2026-10-01/original-plan.md and state/handover-v095-2026-10-01/audit-report.md. Verify fetched branch and e40785633f83c7e20db76c7a06014215aec06cad ancestry. Substantial implementation exists; this plan closes acceptance gaps. Independent plan review is PENDING. First review it and report readiness. Wait for my execution instruction before implementing. Once authorized, execute bounded steps with independent QA/security, real model/native evidence, measurable spend or a new execution-specific override, and exact-commit hosted CI. Keep unknown historical records UNVERIFIED and unrun mandatory checks PENDING. Preserve tags/releases. Stop before merge until I explicitly approve the reviewed head. Do not add dependencies/services or change credentials/permissions without separate authorization. Commit only plan-relevant sanitized files; return branch/head/PR/CI and blockers.

## Required inputs

- [Execution plan](state/plan-v095-acceptance-remediation-2026-10-01.md): dependencies, scenarios, native entry points, expected exits, evidence paths and completion gates.
- [Original plan](state/handover-v095-2026-10-01/original-plan.md): historical requirements, not renewed release authorization.
- [Full audit](state/handover-v095-2026-10-01/audit-report.md): covered/failed/partial/unverified requirements.
- [Evidence index](state/handover-v095-2026-10-01/evidence-index.md) and [selected evidence](state/handover-v095-2026-10-01/audit-evidence).
- [Preparation status](state/handover-v095-2026-10-01/preparation-status.md): direct validation and independent-review limitation.
- [SHA-256 manifest](state/handover-v095-2026-10-01/SHA256SUMS): payload except itself. Run `sha256sum -c state/handover-v095-2026-10-01/SHA256SUMS` from repository root.

## State and boundaries

PR19 is open at e40785633f83c7e20db76c7a06014215aec06cad with green CI. This branch includes that commit; no merge was performed. Public main was e75f6f94d7b664a145753443d26cfe5d2942970b with failed CI. Published v0.9.5 remains 2fe3bb348977a3837a8ef1fb82197afa537d1200. Refresh remote facts before execution.

Six release surfaces match and strict ledger replay passes. Correct false ledger narrative by appending evidence, not relaxing validation. New verification cannot retrospectively supply pre-publication evidence. No retagging, v0.9.6 or new release.

The user authorized UNKNOWN spend only for this handover, then direct completion with independent review PENDING. Neither override authorizes implementation or release work. Original dirty files and machine-local configuration are excluded. Both terminal networking and connector write approval blocked remote publication; no credential/permission changes were made.
