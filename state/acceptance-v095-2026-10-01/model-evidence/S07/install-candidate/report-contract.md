# Systems-audit report contract

Write one fenced Markdown report. Its body must contain these headings exactly once and
in this order; do not replace them with prose labels:

```markdown
## Summary
Scope: <scope>
Status: <terminal status>
Severity counts: <Critical count> Critical / <Major count> Major / <Minor count> Minor / <Nice count> Nice
## Scope
<designated root, revision, applicable criteria, expected artifacts, exclusions>
## Method
<evidence map, provenance, freshness, contradictions, and limitations>
## Findings
<ordered supported findings, or No findings in inspected surfaces.>
## Fixes
<proposed remedies only; no fix planning without confirmation>
## Improvements
<non-blocking improvements>
## Nice-to-haves
<optional polish>
## Follow-up
<ask whether to plan fixes, then stop>
```

Every report includes the four severity labels in `## Summary`. A clean report sets all
counts to zero and writes exactly `No findings in inspected surfaces.` in `## Findings`.
For findings, use Critical, Major, Minor, Nice order; show no more than five per
department and add exact overflow totals as `+<count> further <Severity> findings withheld
(cap 5)`. A collision is `STATUS REFUSED-OVERWRITE` with no write. Missing or unsupported
scope asks one clarification. `## Fixes` records remedies only after explicit confirmation
to plan fixes. Inaccessible required artifacts or output failure ends as `STATUS INCOMPLETE`.

Before writing, run `prepare-audit-report-path.sh` from the installed runtime as
`<runtime-root>/scripts/ci/prepare-audit-report-path.sh`
with the audited root, allowed scope, and absolute report path. It accepts only a direct
`<project-root>/audits/audit-report-<scope>-*.md` destination and changes no file. A
pre-existing compliant destination returns `STATUS: REFUSED-OVERWRITE`; do not invoke
Write. A `STATUS: READY-WRITE` result permits one Write. For non-clean findings, pipe
every finding from one audit through one formatter invocation as
`Department<TAB>Severity<TAB>finding` rows. The supported canonical department keys are
`Research`, `Product`, `Design`, `Build`, `Quality`, `Docs`, and `Delivery`; `complete`
includes every finding from every audited department. Pipe those rows through
`format-audit-findings.sh` from the installed runtime as
`<runtime-root>/scripts/ci/format-audit-findings.sh` and use its output exactly.
The formatter preserves canonical department order, orders severities within each
department, displays at most five findings per department, and emits each exact overflow
total.

The handoff supplies two absolute paths: an installed runtime root and the audited project
root. Resolve the validator from the runtime root as
`<runtime-root>/scripts/ci/validate-audit-report.sh`; never look for it under the audited
project. After a successful write, run it with `--root <audited-project-root>` and the
explicit report path. Record a failed validation as `INCOMPLETE`; an unrun validation is
`PENDING` with its limitation.
