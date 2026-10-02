# Step 3 leg transcript: S17 / baseline
revision=db5293602a0a795bddde0e618d1732a6ce1c5d64
invocation=AUDIT-VIA-SEFI-AUDIT-COMMAND (v0.9.4 agent path; skill absent)
session=sess-f85e2fe9
prompt_sha256=b6f3dfc6ca77d0250f5bc73881a676a0dee9efaa370f10bffa433306dce0a18b
--- prepare/pathcheck ---
report=[SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S17/project-baseline/audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md
pre_exists=False
--- validation ---
as-installed no-args: exit=0 :: validate-audit-report: OK (0 report(s) checked)
as-installed positional report path: exit=1 :: ERROR: [SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S17/project-baseline/audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md - canonical audits root is unavailable
validate-audit-report: 1 error(s)
relocated shape-only run (unmodified bytes, sha=98af7774868742a2e7da95546e903be43ed413f5a7537e5730817c5a0d7607cb): exit=1 :: ERROR: C:/Windows/Temp/sefi-shape-S17-baseline/audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md - missing skeleton heading '## Summary'
ERROR: C:/Windows/Temp/sefi-shape-S17-baseline/audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md - missing skeleton heading '## Scope'
ERROR: C:/Windows/Temp/sefi-shape-S17-baseline/audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md - missing skeleton heading '## Method'
ERROR: C:/Windows/Temp/sefi-shape-S17-baseline/audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md - missing skeleton heading '## Findings'
ERROR: C:/Windows/Temp/sefi-shape-S17-baseline/audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md - missing skeleton heading '## Fixes'
ERROR: C:/Windows/Temp/sefi-shape-S17-baseline/audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md - missing skeleton heading '## Improvements'
ERROR: C:/Windows/Temp/sefi-shape-S17-baseline/audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md - missing skeleton heading '## Nice-to-haves'
ERROR: C:/Windows/Temp/sefi-shape-S17-baseline/audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md - missing skeleton heading '## Follow-up'
validate-audit-report: 8 error(s)
--- report file: audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md ---
```markdown
# Audit report: quality (S17 baseline, unsupported assertion)
Revision: db5293602a0a795bddde0e618d1732a6ce1c5d64 via /sefi:audit quality.
Coverage: Quality, cross-cutting. Sampled: summary.md (author PASS claim for
rev SYNTH-17, 2026-09-30). Project-tree enumeration shows no execution log on
disk, so the claim has no executed counterpart.

## Quality
- [Major] PASS claim with no execution log; unsupported. Verification PENDING,
  conclusion UNKNOWN; the claim must not be relied on.
```

Quality: 1 major; assertion versus execution recorded with PENDING/UNKNOWN.
Report: audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md.
Whether to plan fixes? Stopping for explicit confirmation.

AUDIT-SCOPE: quality
AUDIT-REPORT: [SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S17/project-baseline/audits/audit-report-quality-2026-10-01-0000-sess-f85e2fe9.md
FINDINGS: 0 critical / 1 major / 0 minor / 0 nice, overflow included
STATUS: COMPLETE
