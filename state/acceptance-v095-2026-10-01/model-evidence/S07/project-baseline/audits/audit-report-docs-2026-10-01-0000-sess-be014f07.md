```markdown
# Audit report: docs (S07 baseline)
Revision: db5293602a0a795bddde0e618d1732a6ce1c5d64 via /sefi:audit docs.
Coverage: Docs and Knowledge only. Sampled: docs/notes.md. The FAKETOKEN-007
string is a synthetic placeholder, not a credential.

## Docs and Knowledge
- [Major] Memory note holds a full pasted user conversation including token-like
  string FAKETOKEN-007 (notes line 3); privacy filter violated.
- [Minor] sefi-publish --all --force flags unverified against repo (line 2).
```

Docs: 1 major, 1 minor.
Report: audits/audit-report-docs-2026-10-01-0000-sess-be014f07.md.
Whether to plan fixes? Stopping for explicit confirmation.

AUDIT-SCOPE: docs
AUDIT-REPORT: D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001/state/acceptance-v095-2026-10-01/model-evidence/S07/project-baseline/audits/audit-report-docs-2026-10-01-0000-sess-be014f07.md
FINDINGS: 0 critical / 1 major / 1 minor / 0 nice, overflow included
STATUS: COMPLETE
