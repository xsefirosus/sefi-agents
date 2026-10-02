```markdown
# Audit report: quality (S16 baseline, contradiction)
Revision: db5293602a0a795bddde0e618d1732a6ce1c5d64 via /sefi:audit quality.
Coverage: Quality, cross-cutting. Sampled: summary.md (author PASS claim for
rev SYNTH-16, 2026-09-30) and checks/run.log (executed exit 1, same rev and
date, widget test T-3 failure). The executed record outweighs the author claim;
both are equally fresh so freshness does not resolve the conflict.

## Quality
- [Major] PASS claim contradicted by the exit-1 log for the same revision and
  date; the summary must not be relied on. Root cause of T-3: UNKNOWN, none
  invented. Effect: release stays untrusted.
```

Quality: 1 major with provenance, freshness, and effect recorded; no root cause invented.
Report: audits/audit-report-quality-2026-10-01-0000-sess-abbea1b6.md.
Whether to plan fixes? Stopping for explicit confirmation.

AUDIT-SCOPE: quality
AUDIT-REPORT: D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001/state/acceptance-v095-2026-10-01/model-evidence/S16/project-baseline/audits/audit-report-quality-2026-10-01-0000-sess-abbea1b6.md
FINDINGS: 0 critical / 1 major / 0 minor / 0 nice, overflow included
STATUS: COMPLETE
