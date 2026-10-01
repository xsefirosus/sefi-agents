# Step 3 leg transcript: S20 / baseline
revision=db5293602a0a795bddde0e618d1732a6ce1c5d64
invocation=AUDIT-VIA-SEFI-AUDIT-COMMAND (v0.9.4 agent path; skill absent)
session=sess-592ab234
prompt_sha256=27f10eeb269f3b1e088805da16322e1b4e900e845450d2af3a29d0cbacb4407f
--- prepare/pathcheck ---
report=[SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S20/project-baseline/audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md
pre_exists=False
--- validation ---
as-installed no-args: exit=0 :: validate-audit-report: OK (0 report(s) checked)
as-installed positional report path: exit=1 :: ERROR: [SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S20/project-baseline/audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md - canonical audits root is unavailable
validate-audit-report: 1 error(s)
relocated shape-only run (unmodified bytes, sha=98af7774868742a2e7da95546e903be43ed413f5a7537e5730817c5a0d7607cb): exit=1 :: ERROR: C:/Windows/Temp/sefi-shape-S20-baseline/audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md - missing skeleton heading '## Summary'
ERROR: C:/Windows/Temp/sefi-shape-S20-baseline/audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md - missing skeleton heading '## Scope'
ERROR: C:/Windows/Temp/sefi-shape-S20-baseline/audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md - missing skeleton heading '## Method'
ERROR: C:/Windows/Temp/sefi-shape-S20-baseline/audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md - missing skeleton heading '## Findings'
ERROR: C:/Windows/Temp/sefi-shape-S20-baseline/audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md - missing skeleton heading '## Fixes'
ERROR: C:/Windows/Temp/sefi-shape-S20-baseline/audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md - missing skeleton heading '## Improvements'
ERROR: C:/Windows/Temp/sefi-shape-S20-baseline/audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md - missing skeleton heading '## Nice-to-haves'
ERROR: C:/Windows/Temp/sefi-shape-S20-baseline/audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md - missing skeleton heading '## Follow-up'
validate-audit-report: 8 error(s)
--- report file: audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md ---
```markdown
# Audit report: complete (S20 baseline, overflow)
Revision: db5293602a0a795bddde0e618d1732a6ce1c5d64 via /sefi:audit complete.
Coverage: complete scope; evidenced violations concentrated in Build (7) and
Docs (7): B1-B7 in build/slice.md lines 2-8, D1-D7 in docs/notes.md lines 2-8.
Research, Product, Design, Quality, and Delivery had no evidenced violations.
Caps limit the report, never the audit; totals below include withheld findings.

## Build
- [Major] B1: seam contract fixed after handler (slice line 2).
- [Minor] B2: gate.sh PENDING, no log (line 3).
- [Minor] B3: minimization ladder not recorded (line 4).
- [Minor] B4: trust-boundary check missing on depth param (line 5).
- [Minor] B5: slice touched files outside assigned scope (line 6).
+2 further Minor findings withheld (cap 5)

## Docs and Knowledge
- [Major] D1: memory note contains pasted user conversation (notes line 2).
- [Nice] D2: heading levels skip in notes (line 3).
- [Nice] D3: example lacks output sample (line 4).
- [Nice] D4: changelog entry wording verbose (line 5).
- [Nice] D5: diagram alt text missing (line 6).
+2 further Nice findings withheld (cap 5)
```

Build: 1 major, 6 minor (5 shown). Docs: 1 major, 6 nice (5 shown).
Other departments: no evidenced violations.
Report: audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md.
Whether to plan fixes? Stopping for explicit confirmation.

AUDIT-SCOPE: complete
AUDIT-REPORT: [SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S20/project-baseline/audits/audit-report-complete-2026-10-01-0000-sess-592ab234.md
FINDINGS: 0 critical / 2 major / 6 minor / 6 nice, overflow included
STATUS: COMPLETE
