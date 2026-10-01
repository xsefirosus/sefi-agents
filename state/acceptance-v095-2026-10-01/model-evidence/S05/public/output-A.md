# Step 3 leg transcript: S05 / baseline
revision=db5293602a0a795bddde0e618d1732a6ce1c5d64
invocation=AUDIT-VIA-SEFI-AUDIT-COMMAND (v0.9.4 agent path; skill absent)
session=sess-a46f56a2
prompt_sha256=d765e371b49f36b6173ee1e85aafc5a009166618fbb716233760db78f67e38ad
--- prepare/pathcheck ---
report=[SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S05/project-baseline/audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md
pre_exists=False
--- validation ---
as-installed no-args: exit=0 :: validate-audit-report: OK (0 report(s) checked)
as-installed positional report path: exit=1 :: ERROR: [SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S05/project-baseline/audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md - canonical audits root is unavailable
validate-audit-report: 1 error(s)
relocated shape-only run (unmodified bytes, sha=98af7774868742a2e7da95546e903be43ed413f5a7537e5730817c5a0d7607cb): exit=1 :: ERROR: C:/Windows/Temp/sefi-shape-S05-baseline/audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md - missing skeleton heading '## Summary'
ERROR: C:/Windows/Temp/sefi-shape-S05-baseline/audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md - missing skeleton heading '## Scope'
ERROR: C:/Windows/Temp/sefi-shape-S05-baseline/audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md - missing skeleton heading '## Method'
ERROR: C:/Windows/Temp/sefi-shape-S05-baseline/audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md - missing skeleton heading '## Findings'
ERROR: C:/Windows/Temp/sefi-shape-S05-baseline/audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md - missing skeleton heading '## Fixes'
ERROR: C:/Windows/Temp/sefi-shape-S05-baseline/audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md - missing skeleton heading '## Improvements'
ERROR: C:/Windows/Temp/sefi-shape-S05-baseline/audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md - missing skeleton heading '## Nice-to-haves'
ERROR: C:/Windows/Temp/sefi-shape-S05-baseline/audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md - missing skeleton heading '## Follow-up'
validate-audit-report: 8 error(s)
--- report file: audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md ---
```markdown
# Audit report: build (S05 baseline)
Revision: db5293602a0a795bddde0e618d1732a6ce1c5d64 via /sefi:audit build.
Coverage: Build only. Sampled: build/slice.md.

## Build
- [Major] Seam contract fixed after handler plus trust-boundary validation absent
  on queue-depth (slice lines 3, 5).
- [Minor] gate.sh PENDING with no log (slice line 4).
```

Build: 1 major, 1 minor.
Report: audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md.
Whether to plan fixes? Stopping for explicit confirmation.

AUDIT-SCOPE: build
AUDIT-REPORT: [SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S05/project-baseline/audits/audit-report-build-2026-10-01-0000-sess-a46f56a2.md
FINDINGS: 0 critical / 1 major / 1 minor / 0 nice, overflow included
STATUS: COMPLETE
