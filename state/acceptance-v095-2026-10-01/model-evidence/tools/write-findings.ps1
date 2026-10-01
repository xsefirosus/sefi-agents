#!/usr/bin/env pwsh
# Producer-authored candidate finding determinations (model leg content, TSV for the formatter).
$ErrorActionPreference = 'Stop'
$WT = 'D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'
$EV = "$WT/state/acceptance-v095-2026-10-01/model-evidence"
function WU($path, $text) {
  $dir = Split-Path $path -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}
$T = "`t"
$NL = "`n"
WU "$EV/S01/raw/findings-candidate.tsv" (
  "Research" + $T + "Minor" + $T + "R2/R3 lack confidence and license/provenance mapping (research/digest.md lines 3-4); affected claims stay untrusted until mapped." + $NL +
  "Product" + $T + "Major" + $T + "plan.md has no Done Criteria and no Stage 0 with one uncountable step (product/plan.md lines 2-6); plan stays untrusted until fixed." + $NL +
  "Design" + $T + "Minor" + $T + "three variants present but no selection recorded (design/variants.md line 3); record at convenience." + $NL +
  "Build" + $T + "Minor" + $T + "gate.sh PENDING with no log (build/slice.md line 3); done claim unverifiable until run." + $NL +
  "Docs" + $T + "Minor" + $T + "sefi-deploy --fast flag unverified against repo (docs/notes.md line 2); verify before use." + $NL +
  "Delivery" + $T + "Minor" + $T + "timeout class not recorded (delivery/run.md line 2); record at convenience." + $NL)
WU "$EV/S02/raw/findings-candidate.tsv" (
  "Research" + $T + "Major" + $T + "Q2/Q3 systematically lack confidence, provenance, and Adopt/Defer/Reject reasons (research/digest.md lines 3-4); digest stays untrusted until mapped." + $NL +
  "Research" + $T + "Minor" + $T + "Q1 freshness 11 days old, observed 2026-09-20 (research/digest.md line 2); re-observe at convenience." + $NL)
WU "$EV/S03/raw/findings-candidate.tsv" (
  "Product" + $T + "Major" + $T + "steps are not grep-countable and no Done Criteria exist (product/plan.md lines 2-4); plan stays untrusted until fixed." + $NL +
  "Product" + $T + "Minor" + $T + "no Stage 0 and vague constraints (product/plan.md line 6); restate at convenience." + $NL)
WU "$EV/S04/raw/findings-candidate.tsv" (
  "Design" + $T + "Major" + $T + "single isolated variant only, B/C missing and no selection recorded (design/variants.md lines 2-3); direction stays untrusted until fixed." + $NL +
  "Design" + $T + "Nice" + $T + "a thumbnail sheet of future variants would ease selection; optional polish, never a work order." + $NL)
WU "$EV/S05/raw/findings-candidate.tsv" (
  "Build" + $T + "Major" + $T + "seam contract fixed after handler plus trust-boundary validation absent on queue-depth (build/slice.md lines 3,5); slice stays untrusted until fixed." + $NL +
  "Build" + $T + "Minor" + $T + "gate.sh PENDING with no log (build/slice.md line 4); run at convenience." + $NL)
WU "$EV/S06/raw/findings-candidate.tsv" (
  "Quality" + $T + "Major" + $T + "verdict cites the author report only with zero executed evidence attached (quality/verdict.md lines 2-3); verdict stays untrusted until evidenced." + $NL +
  "Quality" + $T + "Minor" + $T + "delete-the-line integration test not shown (quality/verdict.md line 4); attach at convenience." + $NL)
WU "$EV/S07/raw/findings-candidate.tsv" (
  "Docs" + $T + "Major" + $T + "memory note holds a full pasted user conversation including token-like string FAKETOKEN-007 (docs/notes.md line 3); privacy filter violated, remove before use." + $NL +
  "Docs" + $T + "Minor" + $T + "sefi-publish --all --force flags unverified against repo (docs/notes.md line 2); verify at convenience." + $NL)
WU "$EV/S08/raw/findings-candidate.tsv" (
  "Delivery" + $T + "Major" + $T + "no worktree provenance and rev UNKNOWN (delivery/run.md line 2); deployment stays untrusted until provenanced." + $NL +
  "Delivery" + $T + "Minor" + $T + "timeout class and inbox consume-before-act unrecorded (delivery/run.md line 3); record at convenience." + $NL)
WU "$EV/S10/raw/findings-candidate.tsv" (
  "Build" + $T + "Minor" + $T + "minimization ladder not recorded (build/slice.md line 3); gate PASS log present, so record at convenience." + $NL)
WU "$EV/S14/raw/findings-candidate.tsv" (
  "Research" + $T + "Major" + $T + "no research digest, map, or plan on disk (research/ and product/ absent); later departments SKIPPED-TRIAGE per the foundational rule, audit stops here." + $NL)
WU "$EV/S16/raw/findings-candidate.tsv" (
  "Quality" + $T + "Major" + $T + "summary claims PASS for rev SYNTH-16 on 2026-09-30 but checks/run.log for the same rev and date records exit 1 on widget test T-3; pass claim contradicted, release stays untrusted; root cause UNKNOWN (not evidenced). Effect: the summary must not be relied on." + $NL)
WU "$EV/S17/raw/findings-candidate.tsv" (
  "Quality" + $T + "Major" + $T + "summary claims PASS for rev SYNTH-17 with no execution log on disk; claim unsupported, verification PENDING, conclusion UNKNOWN." + $NL)
WU "$EV/S20/raw/findings-candidate.tsv" (
  "Build" + $T + "Major" + $T + "B1: seam contract fixed after handler (build/slice.md line 2); slice stays untrusted until reordered." + $NL +
  "Build" + $T + "Minor" + $T + "B2: gate.sh PENDING, no log (build/slice.md line 3)." + $NL +
  "Build" + $T + "Minor" + $T + "B3: minimization ladder not recorded (build/slice.md line 4)." + $NL +
  "Build" + $T + "Minor" + $T + "B4: trust-boundary check missing on depth param (build/slice.md line 5)." + $NL +
  "Build" + $T + "Minor" + $T + "B5: slice touched files outside assigned scope (build/slice.md line 6)." + $NL +
  "Build" + $T + "Minor" + $T + "B6: worktree provenance lacks session id (build/slice.md line 7)." + $NL +
  "Build" + $T + "Minor" + $T + "B7: handler/core boundary untested (build/slice.md line 8)." + $NL +
  "Docs" + $T + "Major" + $T + "D1: memory note contains pasted user conversation (docs/notes.md line 2); remove before use." + $NL +
  "Docs" + $T + "Nice" + $T + "D2: heading levels skip in notes (docs/notes.md line 3)." + $NL +
  "Docs" + $T + "Nice" + $T + "D3: example lacks output sample (docs/notes.md line 4)." + $NL +
  "Docs" + $T + "Nice" + $T + "D4: changelog entry wording verbose (docs/notes.md line 5)." + $NL +
  "Docs" + $T + "Nice" + $T + "D5: diagram alt text missing (docs/notes.md line 6)." + $NL +
  "Docs" + $T + "Nice" + $T + "D6: stale link to moved page (docs/notes.md line 7)." + $NL +
  "Docs" + $T + "Nice" + $T + "D7: typo in appendix title (docs/notes.md line 8)." + $NL)
WU "$EV/S22/raw/findings-candidate.tsv" (
  "Build" + $T + "Major" + $T + "seam contract fixed after handler (build/slice.md line 2); slice stays untrusted until reordered. gate PASS log noted, does not clear the ordering gap." + $NL)
Write-Output 'tsv done'
