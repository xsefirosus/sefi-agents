---
name: systems-audit
description: Run an on-demand evidence-based audit of Sefi department outputs through Systems Auditor, with bounded scope, honest coverage, capped findings, and an ignored-local report.
managed-by: sefi-agents
---

# Systems audit

Use only for explicit Sefi department-audit intent or an explicit `systems-audit` skill
invocation. Route through the top-level orchestrator to `systems-auditor`; the auditor
loads [the evidence method](references/evidence-method.md) and [report contract](references/report-contract.md),
never dispatches, and never modifies source. Keep ordinary UI, security, and code-review
requests on their established routes.

Accept only `complete`, `research`, `product`, `design`, `build`, `quality`, `docs`, or
`delivery`. For a missing or unsupported scope, ask one clarification and do not assume
`complete`. `complete` covers all departments, but disclose sampling and never claim every
artifact was inspected.

The Systems Auditor agent is authoritative for department criteria. The repository's
`docs/AUDIT-DEPARTMENTS.md` may supplement reader context when available; installed audit
behavior does not depend on checkout-only documentation. Preserve department order,
foundational Research/Product triage, four severities, five displayed findings per
department, and exact overflow totals. Report once under `audits/`, refuse collisions, and
ask for explicit confirmation before fix planning.

The installed runtime root and audited project root are separate handoff values. Resolve
the validator from the runtime root, then run it with the audited root and explicit report
path as specified by the report contract. Use `INCOMPLETE` for inaccessible required
artifacts or output failure; never call an unread audit complete. Clean reports list all
severity counts as zero and say `No findings in inspected surfaces.`

Follow [anti-hallucination](../anti-hallucination/SKILL.md): unsupported conclusions are
`UNKNOWN` and checks not run are `PENDING`.
