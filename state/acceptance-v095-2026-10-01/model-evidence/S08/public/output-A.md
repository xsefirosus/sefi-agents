# Step 3 leg transcript: S08 / baseline
revision=db5293602a0a795bddde0e618d1732a6ce1c5d64
invocation=AUDIT-VIA-SEFI-AUDIT-COMMAND (v0.9.4 agent path; skill absent)
session=sess-abf4469d
prompt_sha256=4cb7b8534bd559cd0a22e55b44555a7ee709116e33abe84d815262c567f597fd
--- prepare/pathcheck ---
report=[SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S08/project-baseline/audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md
pre_exists=False
--- validation ---
as-installed no-args: exit=0 :: validate-audit-report: OK (0 report(s) checked)
as-installed positional report path: exit=1 :: ERROR: [SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S08/project-baseline/audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md - canonical audits root is unavailable
validate-audit-report: 1 error(s)
relocated shape-only run (unmodified bytes, sha=98af7774868742a2e7da95546e903be43ed413f5a7537e5730817c5a0d7607cb): exit=1 :: ERROR: C:/Windows/Temp/sefi-shape-S08-baseline/audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md - missing skeleton heading '## Summary'
ERROR: C:/Windows/Temp/sefi-shape-S08-baseline/audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md - missing skeleton heading '## Scope'
ERROR: C:/Windows/Temp/sefi-shape-S08-baseline/audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md - missing skeleton heading '## Method'
ERROR: C:/Windows/Temp/sefi-shape-S08-baseline/audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md - missing skeleton heading '## Findings'
ERROR: C:/Windows/Temp/sefi-shape-S08-baseline/audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md - missing skeleton heading '## Fixes'
ERROR: C:/Windows/Temp/sefi-shape-S08-baseline/audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md - missing skeleton heading '## Improvements'
ERROR: C:/Windows/Temp/sefi-shape-S08-baseline/audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md - missing skeleton heading '## Nice-to-haves'
ERROR: C:/Windows/Temp/sefi-shape-S08-baseline/audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md - missing skeleton heading '## Follow-up'
validate-audit-report: 8 error(s)
--- report file: audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md ---
```markdown
# Audit report: delivery (S08 baseline)
Revision: db5293602a0a795bddde0e618d1732a6ce1c5d64 via /sefi:audit delivery.
Coverage: Delivery and Infra only. Sampled: delivery/run.md.

## Delivery and Infra
- [Major] No worktree provenance and rev UNKNOWN (run line 2).
- [Minor] Timeout class and inbox consume-before-act unrecorded (line 3).
```

Delivery: 1 major, 1 minor.
Report: audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md.
Whether to plan fixes? Stopping for explicit confirmation.

AUDIT-SCOPE: delivery
AUDIT-REPORT: [SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S08/project-baseline/audits/audit-report-delivery-2026-10-01-0000-sess-abf4469d.md
FINDINGS: 0 critical / 1 major / 1 minor / 0 nice, overflow included
STATUS: COMPLETE
