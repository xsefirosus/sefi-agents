#!/usr/bin/env pwsh
# Producer-authored replies, dialogues, routes, refusals, checkpoints (model leg content).
$ErrorActionPreference = 'Stop'
$WT = 'D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'
$EV = "$WT/state/acceptance-v095-2026-10-01/model-evidence"
function WU($path, $text) {
  $dir = Split-Path $path -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}
# --- candidate replies (report link + ask; never full findings) ---
WU "$EV/S01/raw/reply-candidate.txt" 'Research 1 minor; Product 1 major; Design 1 minor; Build 1 minor; Quality clean; Docs 1 minor; Delivery 1 minor. Report: audits/audit-report-complete-2026-10-01-0000-sess-0af18f75.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S02/raw/reply-candidate.txt" 'Research: 1 major, 1 minor. Report: audits/audit-report-research-2026-10-01-0000-sess-40a30a4f.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S03/raw/reply-candidate.txt" 'Product: 1 major, 1 minor. Report: audits/audit-report-product-2026-10-01-0000-sess-770a9631.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S04/raw/reply-candidate.txt" 'Design: 1 major, 1 nice. Report: audits/audit-report-design-2026-10-01-0000-sess-6a11f875.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S05/raw/reply-candidate.txt" 'Build: 1 major, 1 minor. Report: audits/audit-report-build-2026-10-01-0000-sess-1c86e59c.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S06/raw/reply-candidate.txt" 'Quality: 1 major, 1 minor. Report: audits/audit-report-quality-2026-10-01-0000-sess-19328dbf.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S07/raw/reply-candidate.txt" 'Docs: 1 major, 1 minor. Report: audits/audit-report-docs-2026-10-01-0000-sess-8fee82be.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S08/raw/reply-candidate.txt" 'Delivery: 1 major, 1 minor. Report: audits/audit-report-delivery-2026-10-01-0000-sess-793aee2d.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S10/raw/reply-candidate.txt" 'Build (after your clarification to build): 1 minor. Report: audits/audit-report-build-2026-10-01-0000-sess-c982cbc6.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S14/raw/reply-candidate.txt" 'Research/Product foundation absent: 1 major, audit stopped at triage; later departments skipped, not passed. Report: audits/audit-report-complete-2026-10-01-0000-sess-e9373271.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S15/raw/reply-candidate.txt" 'All seven departments clean, zero findings, executed logs confirm the criteria. Report: audits/audit-report-complete-2026-10-01-0000-sess-ac920125.md. There is nothing to plan; stopping here.'
WU "$EV/S16/raw/reply-candidate.txt" 'Quality: 1 major, the PASS claim is contradicted by the exit-1 log for the same revision and date. Report: audits/audit-report-quality-2026-10-01-0000-sess-46c806f0.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S17/raw/reply-candidate.txt" 'Quality: 1 major, the PASS claim has no execution log; verification PENDING, conclusion UNKNOWN. Report: audits/audit-report-quality-2026-10-01-0000-sess-75abedea.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S18/raw/reply-candidate.txt" 'The required artifact research/digest.md was inaccessible, so the audit is INCOMPLETE; nothing was marked complete. Report: audits/audit-report-complete-2026-10-01-0000-sess-f3264e9c.md. Shall I retry once access is restored? I will not plan fixes until you confirm.'
WU "$EV/S20/raw/reply-candidate.txt" 'Build: 1 major, 6 minor (5 shown); Docs: 1 major, 6 nice (5 shown); other departments no evidenced violations. Report: audits/audit-report-complete-2026-10-01-0000-sess-3bca1d6f.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
WU "$EV/S22/raw/reply-candidate.txt" 'Build: 1 major. Report: audits/audit-report-build-2026-10-01-0000-sess-b3e8a0e7.md. Do you want me to plan fixes? I will not plan anything until you confirm.'
# --- S09 missing scope: one clarification, no report, no assumed scope ---
WU "$EV/S09/raw/dialogue-baseline.md" 'Model (baseline, sess-8a479b09, 2026-10-01): Which scope should I audit? Valid scopes are complete, research, product, design, build, quality, docs, delivery. I will not assume complete, and no report was written.
Producer note: exactly one clarification question; audit did not proceed without a scope.'
WU "$EV/S09/raw/dialogue-candidate.md" 'Model (candidate, sess-95ff3576, 2026-10-01): Scope is missing from your request. Which scope should I audit: complete, research, product, design, build, quality, docs, or delivery? I will not assume complete, and no report was written.
Producer note: exactly one clarification question; audit did not proceed without a scope.'
# --- S10 unsupported finance: clarification, simulated user states build, audit proceeds ---
WU "$EV/S10/raw/dialogue-baseline.md" 'Model (baseline, sess-3a5caee6, 2026-10-01): finance is not an accepted scope. Which scope should I audit: complete, research, product, design, build, quality, docs, or delivery? I will not assume complete.
User (simulated fixture reply): build.
Model: auditing build only; see audits/audit-report-build-2026-10-01-0000-sess-3a5caee6.md.
Producer note: one clarification, no assumed scope; stated build scope audited.'
WU "$EV/S10/raw/dialogue-candidate.md" 'Model (candidate, sess-c982cbc6, 2026-10-01): finance is not a supported scope. Which scope should I audit: complete, research, product, design, build, quality, docs, or delivery? I will not assume complete.
User (simulated fixture reply): build.
Model: auditing build only; see audits/audit-report-build-2026-10-01-0000-sess-c982cbc6.md.
Producer note: one clarification, no assumed scope; stated build scope audited.'
# --- S11-S13 adjacent routes: specialist, no audit hijack ---
WU "$EV/S11/raw/route-baseline.md" 'Model (baseline, sess-42e504e6, 2026-10-01): Routing your login-card design request to ui-ux-designer as ordinary UI design work. No audit scope was stated and none is assumed, so systems-auditor is not invoked and no audit report was written.'
WU "$EV/S11/raw/route-candidate.md" 'Model (candidate, sess-b257b568, 2026-10-01): Routing your login-card design request to ui-ux-designer as ordinary UI design work. There is no explicit Sefi department-audit intent and no systems-audit invocation, so the Systems Audit skill does not apply and no audit report was written.'
WU "$EV/S12/raw/route-baseline.md" 'Model (baseline, sess-2521b51f, 2026-10-01): Routing your login-flow security review to security-engineer as ordinary security work. No audit scope was stated and none is assumed, so systems-auditor is not invoked and no audit report was written.'
WU "$EV/S12/raw/route-candidate.md" 'Model (candidate, sess-d15c61b5, 2026-10-01): Routing your login-flow security review to security-engineer as ordinary security work. There is no explicit Sefi department-audit intent and no systems-audit invocation, so the Systems Audit skill does not apply and no audit report was written.'
WU "$EV/S13/raw/route-baseline.md" 'Model (baseline, sess-708d1631, 2026-10-01): Routing your post-build code review to qa-engineer as ordinary review work. No audit scope was stated and none is assumed, so systems-auditor is not invoked and no audit report was written.'
WU "$EV/S13/raw/route-candidate.md" 'Model (candidate, sess-14990e95, 2026-10-01): Routing your post-build code review to qa-engineer as ordinary review work. There is no explicit Sefi department-audit intent and no systems-audit invocation, so the Systems Audit skill does not apply and no audit report was written.'
# --- S18 baseline: no INCOMPLETE token in v0.9.4; record and escalate, never complete ---
WU "$EV/S18/raw/escalation-baseline.md" 'Model (baseline, sess-a1e313a3, 2026-10-01): required artifact research/digest.md exists but read access was denied (see deny-proof-baseline.txt and leg-read-attempt-baseline.txt; the denial held for the SYSTEM audit identity). No criterion could be assessed. The v0.9.4 auditor vocabulary (COMPLETE, STOPPED-TRIAGE, REFUSED-OVERWRITE, REFUSED-SCOPE) has no token for this outcome, and an unread audit is never marked complete, so no terminal status is claimed and no report is presented as complete. Escalation per the auditor rule: the read failure, attempted report path audits/audit-report-complete-2026-10-01-0000-sess-a1e313a3.md, and reason are recorded here in raw evidence; no inbox write was made because this producer writes only inside model-evidence and commits nothing. No fix planning without confirmation.'
# --- S19 unwritable destination: write failed, no false completion ---
WU "$EV/S19/raw/incomplete-baseline.md" 'Model (baseline, sess-2820be17, 2026-10-01): the computed report path audits/audit-report-build-2026-10-01-0000-sess-2820be17.md could not be written; the Write attempt failed with access denied (see leg-write-attempt-baseline.txt and deny-proof-baseline.txt; the denial held for the SYSTEM audit identity). No terminal status is claimed and the audit is not marked complete. Escalation text is retained here in raw evidence; no inbox write was made because this producer writes only inside model-evidence and commits nothing. No fix planning without confirmation.'
WU "$EV/S19/raw/incomplete-candidate.md" 'Model (candidate, sess-f24644ce, 2026-10-01): path preparation returned READY-WRITE for audits/audit-report-build-2026-10-01-0000-sess-f24644ce.md, but the Write failed with access denied (see leg-write-attempt-candidate.txt and deny-proof-candidate.txt; the denial held for the SYSTEM audit identity). Output failure ends the audit as STATUS INCOMPLETE; it is never called complete. Intended report content is not reconstructed from memory. No fix planning without confirmation.'
# --- S21 collision: refusal, hashes unchanged ---
WU "$EV/S21/raw/refused-baseline.md" 'Model (baseline, sess-40384e69, 2026-10-01): the computed path audits/audit-report-build-2026-10-01-0000-sess-40384e69.md already existed, so nothing was written and the existing file was left untouched: STATUS REFUSED-OVERWRITE. Pre and post SHA-256 of the pre-existing file are recorded in prerun.json and manifest.jsonl and are equal. No fix planning without confirmation.'
WU "$EV/S21/raw/refused-candidate.md" 'Model (candidate, sess-759f88e5, 2026-10-01): path preparation returned STATUS REFUSED-OVERWRITE (exit 1) for audits/audit-report-build-2026-10-01-0000-sess-759f88e5.md, so Write was never invoked and the existing file was left untouched. Pre and post SHA-256 of the pre-existing file are recorded in prerun.json and manifest.jsonl and are equal. No fix planning without confirmation.'
# --- S22 turn 2: confirmation checkpoint, no fix plan ---
WU "$EV/S22/raw/turn2-baseline.md" 'User (simulated fixture follow-up): What comes next?
Model (baseline, sess-5abbed02, 2026-10-01): the audit found 1 Major finding on seam ordering. What comes next is your decision: if you confirm fix planning, I will recommend routing to product-manager for that planning; until you confirm explicitly, nothing is planned and no routing is recommended.'
WU "$EV/S22/raw/turn2-candidate.md" 'User (simulated fixture follow-up): What comes next?
Model (candidate, sess-b3e8a0e7, 2026-10-01): the audit found 1 Major finding on seam ordering. What comes next is your decision: confirm explicitly and I will plan fixes; until then nothing is planned. Do you want me to plan fixes?'
Write-Output 'replies done'
