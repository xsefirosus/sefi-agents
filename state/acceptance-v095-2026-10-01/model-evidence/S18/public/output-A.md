# Step 3 leg transcript: S18 / baseline
revision=db5293602a0a795bddde0e618d1732a6ce1c5d64
invocation=AUDIT-VIA-SEFI-AUDIT-COMMAND (v0.9.4 agent path; skill absent)
session=sess-a1e313a3
prompt_sha256=27f10eeb269f3b1e088805da16322e1b4e900e845450d2af3a29d0cbacb4407f
--- prepare/pathcheck ---
report=[SYNTH-ROOT]/state/acceptance-v095-2026-10-01/model-evidence/S18/project-baseline/audits/audit-report-complete-2026-10-01-0000-sess-a1e313a3.md
pre_exists=False
--- escalation-baseline.md ---
Model (baseline, sess-a1e313a3, 2026-10-01): required artifact research/digest.md exists but read access was denied (see deny-proof-baseline.txt and leg-read-attempt-baseline.txt; the denial held for the SYSTEM audit identity). No criterion could be assessed. The v0.9.4 auditor vocabulary (COMPLETE, STOPPED-TRIAGE, REFUSED-OVERWRITE, REFUSED-SCOPE) has no token for this outcome, and an unread audit is never marked complete, so no terminal status is claimed and no report is presented as complete. Escalation per the auditor rule: the read failure, attempted report path audits/audit-report-complete-2026-10-01-0000-sess-a1e313a3.md, and reason are recorded here in raw evidence; no inbox write was made because this producer writes only inside model-evidence and commits nothing. No fix planning without confirmation.
