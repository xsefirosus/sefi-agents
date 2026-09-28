# Systems-audit evidence method

This method adapts audit ideas to a small, on-demand engineering review. No certification claim is made; it does not assert conformity with any standard.

## 1. Define the audit

Record the selected scope, designated project root, revision, applicable criteria,
expected artifacts, and exclusions. Use the Systems Auditor agent for department
criteria; the department record is supporting context. Ask once when scope is missing or
unsupported.

## 2. Map evidence

Map every applicable criterion to inspected artifacts or an executed check. Record each
item's provenance, freshness, contradictions, and limitations. An author claim is evidence
to test, not proof that a condition holds.

## 3. Choose coverage

Assess every applicable criterion. Select artifact samples by risk, state what was sampled,
and disclose omitted surfaces. A `complete` audit includes all seven departments but does
not mean every artifact was inspected.

## 4. Verify selectively

Inspect source and run bounded checks only when they answer a concrete question. Check a
command for side effects before running it. Record command, target, outcome, and relevant
evidence. Mark an unrun check `PENDING`; use `UNKNOWN` when evidence cannot support the
conclusion.

## 5. Develop findings

For each finding, cite the criterion, observed condition, evidence, severity rationale,
and effect. State a root cause only when the evidence supports it. Keep proposed remedies
separate from findings.

## 6. Report accurately

State coverage and limitations, preserve report caps and overflow totals, and do not treat
a structurally valid report as proof of correctness. An inaccessible required artifact or
output failure ends with `INCOMPLETE`, never `COMPLETE`.

## Sources and adaptations

- [ISO 19011](https://www.iso.org/standard/19011) informs defining scope, evidence,
  competence boundaries, and recording limitations.
- [NIST SP 800-53A](https://csrc.nist.gov/pubs/sp/800/53/a/r5/final) informs criterion to
  evidence mapping and assessment evidence that is specific enough to rerun.
- [IIA Global Internal Audit Standards](https://www.theiia.org/en/standards/2024-standards/global-internal-audit-standards/)
  informs evidence-supported conclusions and clear communication of limitations.
- [GAO Government Auditing Standards](https://www.gao.gov/assets/d24106786.pdf) informs
  sufficient, appropriate evidence and separating observations from recommendations.

These are adaptations for this skill, not a certification claim or a representation of
conformance with ISO, NIST, IIA, or GAO requirements.
