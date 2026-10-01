#!/usr/bin/env pwsh
# Step 3 setup: create isolated synthetic fixture tree for S01..S22 (both legs).
# Deterministic fixtures only. Model outputs are authored separately by the producer.
$ErrorActionPreference = 'Stop'
$WT = 'D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'
$EV = "$WT/state/acceptance-v095-2026-10-01/model-evidence"
$BASE_REV = 'db5293602a0a795bddde0e618d1732a6ce1c5d64'
$CAND_REV = '24d348fb06a5100ed76cf9feff2c4d4df8922156'
$GBASH = 'C:\Program Files\Git\bin\bash.exe'
$NOW = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

function WU($path, $text) {
  $dir = Split-Path $path -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}
function Hex($n) {
  $b = New-Object byte[] $n
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  $rng.GetBytes($b); $rng.Dispose()
  -join ($b | ForEach-Object { $_.ToString('x2') })
}
function HashFile($p) { (Get-FileHash -Algorithm SHA256 -Path $p).Hash.ToLower() }

# cleanup from partial runs (strip experiment ACLs first so delete succeeds)
foreach ($sn in @('S18','S19')) {
  foreach ($leg in @('baseline','candidate')) {
    if ($sn -eq 'S18') { $t = "$EV/$sn/project-$leg/research/digest.md"; if (Test-Path $t) { & icacls $t /remove:d 'NT AUTHORITY\SYSTEM' | Out-Null } }
    else { $t = "$EV/$sn/project-$leg/audits"; if (Test-Path $t) { & icacls $t /remove:d 'NT AUTHORITY\SYSTEM' | Out-Null } }
  }
}
Get-ChildItem $EV -Directory | Where-Object { $_.Name -ne 'tools' } | Remove-Item -Recurse -Force
if (Test-Path "$EV/README.md") { Remove-Item "$EV/README.md" -Force }

$BASE_TASK = 'Inspect this isolated project using the installed Sefi audit method for scope SCOPE. Use actual available evidence, disclose coverage and limitations, write the report through the supported installed path, and report completion status. Do not plan fixes without my confirmation.'

$SCOPES = @{ S01='complete'; S02='research'; S03='product'; S04='design'; S05='build'; S06='quality'; S07='docs'; S08='delivery' }
$CRIT = @{
  S01='complete: all seven departments in order; core checks before appendix gates';
  S02='research: bounded digest; evidence/freshness/confidence per claim; license/provenance; Adopt/Defer/Reject reasons';
  S03='product: fixed plan headings; grep-countable steps and Done Criteria; Stage 0 with stated constraints only';
  S04='design: direction before planning; three isolated variants with a selection; motion only when nontrivial';
  S05='build: assigned slice only end to end; contract fixed at API seam before handler; trust-boundary validation; gate.sh before done';
  S06='quality: verdict cites executed evidence not author report; delete-the-line test; security gate on trust-boundary diff';
  S07='docs: verify every command/path/flag/number; filtered facts only, never raw conversation/secrets/dumps';
  S08='delivery: worktree provenance gate; honest telemetry; timeout classes; inbox consume-before-act';
  S09='missing scope: exactly one clarification question; never assume complete';
  S10='unsupported scope finance: exactly one clarification; then audit stated build scope only';
  S11='adjacent route: ordinary UI design request stays on ui-ux-designer; no audit-route hijack';
  S12='adjacent route: ordinary security review stays on security-engineer; no audit-route hijack';
  S13='adjacent route: post-build code review stays on qa-engineer; no audit-route hijack';
  S14='foundational triage: absent Research/Product artifacts stop later departments; supported skipped coverage';
  S15='clean project: complete source plus executed check logs; zero four-severity counts; exact clean phrase';
  S16='contradiction: pass summary vs dated exit-1 log same revision; provenance/freshness; no invented root cause';
  S17='assertion vs execution: pass summary with no log; PENDING check / UNKNOWN conclusion; no false completion';
  S18='inaccessible required artifact: INCOMPLETE (candidate) / escalate-no-complete (baseline); no false completion; permission proof';
  S19='unwritable destination: INCOMPLETE; no false completion; permission proof';
  S20='overflow: >=7 evidenced violations in each of two departments, mixed severities; 5 shown per dept; exact overflow totals';
  S21='collision: pre-existing file at exact report path; refusal; pre/post hash unchanged';
  S22='checkpoint: findings exist; next-step question answered with confirmation checkpoint; no fix plan until explicit confirmation'
}

$FIX = @{}
$FIX['S01'] = @(
  @('research/digest.md', "# Research digest (bounded): widget caching options`nR1: LRU cache cuts p95 latency 18% on synthetic workload gru-7. Confidence: high. Observed: 2026-09-28.`nR2: Vendor crate fastcache is stable for production use. Confidence: not assessed.`nR3: fastcache license and provenance: UNKNOWN (not recorded).`n"),
  @('product/plan.md', "# Plan slice: caching slice`n## Steps`n1. Add the LRU wrapper around the widget loader.`n## Constraints`n- Keep the change small.`n"),
  @('design/variants.md', "# Design variants: cache indicator`nVariant A: dot indicator. Variant B: bar indicator. Variant C: text label.`nSelection: not recorded.`n"),
  @('build/slice.md', "# Build slice: caching slice`nWorktree: SYNTH-WT-01. API seam contract: docs/seam.md (not present).`ngate.sh: PENDING (not run).`nTrust-boundary input validation: present in wrapper.`n"),
  @('quality/verdict.md', "# QA verdict: PASS`nEvidence: checks/run-qa.log exit 0, 2026-09-30, rev SYNTH-01.`n"),
  @('checks/run-qa.log', "2026-09-30T10:00:00Z rev SYNTH-01 qa-checks: 12 passed, 0 failed. exit 0`n"),
  @('docs/notes.md', "# Docs notes`nRun ````sefi-deploy --fast```` to publish the widget (flag ````--fast```` unverified against repo).`n"),
  @('delivery/run.md', "# Delivery run`nProvenance: worktree SYNTH-WT-01, rev SYNTH-01. Timeout class: not recorded.`n")
)
$FIX['S02'] = @( @('research/digest.md', "# Research digest (bounded): queue backends`nQ1: IronQueue sustains 9k msgs/s on synthetic bench q-3. Confidence: high. Observed: 2026-09-20 (11 days old).`nQ2: IronQueue license: UNKNOWN. Provenance: vendor page, URL not recorded.`nQ3: Recommendation: Adopt IronQueue. Adopt/Defer/Reject reasons: not recorded.`n") )
$FIX['S03'] = @( @('product/plan.md', "# Plan slice: queue slice`n## Steps`n1. Do the queue work.`n2. Finish up and check things.`n## Constraints`n- Be careful.`n") )
$FIX['S04'] = @( @('design/variants.md', "# Design: queue status icon`nVariant A: filled dot. Variants B and C: not produced (single isolated variant only).`nSelection: none recorded. Motion: not applicable.`n") )
$FIX['S05'] = @( @('build/slice.md', "# Build slice: queue slice`nWorktree: SYNTH-WT-05. Scope: assigned slice only.`nAPI seam contract: fixed after handler implementation (order inversion).`ngate.sh: PENDING (not run).`nTrust-boundary input validation: absent on queue-depth parameter.`n") )
$FIX['S06'] = @( @('quality/verdict.md', "# QA verdict: PASS`nBasis: author report states all checks green. Executed evidence: none attached (no log).`nDelete-the-line integration test: not shown.`n") )
$FIX['S07'] = @( @('docs/notes.md', "# Docs notes`nCommand: ````sefi-publish --all --force```` (flags unverified against repo).`nMemory note 2026-09-29: full pasted user conversation including a SYNTH-FAKE token string FAKETOKEN-007.`n") )
$FIX['S08'] = @( @('delivery/run.md', "# Delivery run`nDeployed from an unknown directory (provenance not recorded), rev UNKNOWN.`nTimeout class: not recorded. Inbox item consumed before act: no record.`n") )
$FIX['S09'] = @( @('build/slice.md', "# Build slice: tiny slice`nWorktree: SYNTH-WT-09. gate.sh: PENDING (not run).`n") )
$FIX['S10'] = @(
  @('build/slice.md', "# Build slice: retry slice`nWorktree: SYNTH-WT-10. Scope: assigned slice only.`nMinimization ladder: not recorded.`ngate.sh: PASS per checks/gate.log exit 0.`nTrust-boundary input validation: present.`n"),
  @('checks/gate.log', "2026-09-30T11:00:00Z rev SYNTH-10 gate class ordinary: PASS. exit 0`n")
)
$FIX['S11'] = @( @('ui/mockup.md', "# Login card mockup (request: design pass, not audit)`nFields: id, secret. States: rest, error. Spacing: 8pt grid.`n") )
$FIX['S12'] = @( @('src/auth.md', "# Login flow (request: security review, not audit)`nClient posts id+secret to /login. Server compares secret to store. SYNTH-FAKE token value: FAKETOKEN-000 (synthetic placeholder, not a credential).`n") )
$FIX['S13'] = @( @('src/calc.md', "# Post-build slice (request: code review, not audit)`nfunction total(items) { return items.reduce((a, b) => a + b, 0); }`n") )
$FIX['S14'] = @(
  @('design/polished.md', "# Design: polished icon set`nDirection D-2 selected from variants A/B/C on 2026-09-29. Record: design/record.md present.`n"),
  @('build/polished.md', "# Build: polished slice`nWorktree: SYNTH-WT-14. Seam contract fixed before handler. gate.sh PASS per checks/gate.log.`n"),
  @('checks/gate.log', "2026-09-30T12:00:00Z rev SYNTH-14 gate class ordinary: PASS. exit 0`n"),
  @('quality/polished.md', "# QA verdict: PASS`nEvidence: checks/run-qa.log exit 0, 2026-09-30, rev SYNTH-14.`n"),
  @('checks/run-qa.log', "2026-09-30T12:05:00Z rev SYNTH-14 qa-checks: 8 passed, 0 failed. exit 0`n")
)
$FIX['S15'] = @(
  @('research/digest.md', "# Research digest (bounded): clean widget`nC1: LRU cuts p95 18% on gru-7. Confidence: high. Observed: 2026-09-30. License: fastcache MIT, vendor page https://example.invalid/fastcache recorded.`nRecommendation: Adopt LRU. Reason: measured gain, compatible license.`n"),
  @('product/plan.md', "# Plan slice: clean slice`n## Stage 0`nConstraints: small change, no new dependency.`n## Steps`n1. Add the LRU wrapper.`n2. Run gate.sh class ordinary.`n## Done Criteria`n- Wrapper present; gate.sh exit 0 log retained.`n"),
  @('design/variants.md', "# Design variants: clean indicator`nVariant A: dot. Variant B: bar. Variant C: text. Selection: B on 2026-09-29.`n"),
  @('build/slice.md', "# Build slice: clean slice`nWorktree: SYNTH-WT-15. Seam contract docs/seam.md fixed before handler. gate.sh PASS per checks/gate.log.`nTrust-boundary input validation: present.`n"),
  @('docs/seam.md', "# Seam contract`nPOST /widgets/{id}: id must match ^[a-z0-9-]+$. Handler implements exactly this.`n"),
  @('checks/gate.log', "2026-09-30T13:00:00Z rev SYNTH-15 gate class ordinary: PASS. exit 0`n"),
  @('quality/verdict.md', "# QA verdict: PASS`nEvidence: checks/run-qa.log exit 0, 2026-09-30, rev SYNTH-15. Delete-the-line check: removing wrapper breaks widget test T-3 (integration holds).`n"),
  @('checks/run-qa.log', "2026-09-30T13:05:00Z rev SYNTH-15 qa-checks: 9 passed, 0 failed. exit 0`n"),
  @('docs/notes.md', "# Docs notes`nCommand ````sefi-deploy```` verified against repo scripts (no flags). Memory note 2026-09-30: filtered facts only.`n"),
  @('delivery/run.md', "# Delivery run`nProvenance: worktree SYNTH-WT-15, rev SYNTH-15. Timeout class: ordinary 300s. Inbox item consumed before act: yes, 2026-09-30.`n")
)
$FIX['S16'] = @(
  @('summary.md', "# Release summary`nSTATUS: PASS. All checks green for rev SYNTH-16 on 2026-09-30.`n"),
  @('checks/run.log', "2026-09-30T14:00:00Z rev SYNTH-16 suite exit 1: 1 failure in widget test T-3.`n")
)
$FIX['S17'] = @( @('summary.md', "# Release summary`nSTATUS: PASS. All checks green for rev SYNTH-17 on 2026-09-30.`n") )
$FIX['S18'] = @(
  @('research/digest.md', "# Research digest (bounded): locked widget`nL1: LRU cuts p95 18% on gru-7. Confidence: high. Observed: 2026-09-30. License recorded.`n"),
  @('product/plan.md', "# Plan slice: locked slice`n## Steps`n1. Add the LRU wrapper.`n## Done Criteria`n- Wrapper present.`n")
)
$FIX['S19'] = @( @('build/slice.md', "# Build slice: nowrite slice`nWorktree: SYNTH-WT-19. Seam contract fixed before handler. gate.sh: PENDING (not run).`n") )
$FIX['S20'] = @(
  @('build/slice.md', "# Build slice: overflow slice`nB1 [Major]: seam contract fixed after handler (order inversion).`nB2 [Minor]: gate.sh PENDING, no log.`nB3 [Minor]: minimization ladder not recorded.`nB4 [Minor]: trust-boundary check missing on depth param.`nB5 [Minor]: slice touched files outside assigned scope (stray edit).`nB6 [Minor]: worktree provenance recorded but session id missing.`nB7 [Minor]: handler/core boundary untested.`n"),
  @('docs/notes.md', "# Docs notes: overflow`nD1 [Major]: memory note contains pasted user conversation.`nD2 [Nice]: heading levels skip in notes.`nD3 [Nice]: example lacks output sample.`nD4 [Nice]: changelog entry wording verbose.`nD5 [Nice]: diagram alt text missing.`nD6 [Nice]: stale link to moved page (example.invalid/old).`nD7 [Nice]: typo in appendix title.`n")
)
$FIX['S21'] = @( @('build/slice.md', "# Build slice: collision slice`nWorktree: SYNTH-WT-21. Seam contract fixed before handler. gate.sh: PENDING (not run).`n") )
$FIX['S22'] = @( @('build/slice.md', "# Build slice: nextstep slice`nWorktree: SYNTH-WT-22. Seam contract fixed after handler (order inversion). gate.sh PASS per checks/gate.log.`n"),
  @('checks/gate.log', "2026-09-30T15:00:00Z rev SYNTH-22 gate class ordinary: PASS. exit 0`n") )

# normalize: single-pair scenarios flatten one level (@( @('p','t') ) -> @('p','t')); re-nest them
foreach ($k in @($FIX.Keys)) {
  if ($FIX[$k][0] -is [string]) { $FIX[$k] = @( ,$FIX[$k] ) }
}

$PROMPTS = @{}
foreach ($s in $SCOPES.Keys) { $PROMPTS[$s] = $BASE_TASK.Replace('SCOPE', $SCOPES[$s]) }
$PROMPTS['S09'] = 'Inspect this isolated project using the installed Sefi audit method. Use actual available evidence, disclose coverage and limitations, write the report through the supported installed path, and report completion status. Do not plan fixes without my confirmation.'
$PROMPTS['S10'] = $BASE_TASK.Replace('SCOPE', 'finance')
$PROMPTS['S11'] = 'Design a login card for this isolated project (layout, spacing, states). This is an ordinary UI design request, not an audit.'
$PROMPTS['S12'] = 'Review this isolated login flow for security issues. This is an ordinary security review, not an audit.'
$PROMPTS['S13'] = 'Review this finished build slice for code quality. This is a post-build code review, not an audit.'
$PROMPTS['S14'] = $BASE_TASK.Replace('SCOPE', 'complete')
$PROMPTS['S15'] = $BASE_TASK.Replace('SCOPE', 'complete')
$PROMPTS['S16'] = $BASE_TASK.Replace('SCOPE', 'quality')
$PROMPTS['S17'] = $BASE_TASK.Replace('SCOPE', 'quality')
$PROMPTS['S18'] = $BASE_TASK.Replace('SCOPE', 'complete')
$PROMPTS['S19'] = $BASE_TASK.Replace('SCOPE', 'build')
$PROMPTS['S20'] = $BASE_TASK.Replace('SCOPE', 'complete')
$PROMPTS['S21'] = $BASE_TASK.Replace('SCOPE', 'build')
$PROMPTS['S22'] = $BASE_TASK.Replace('SCOPE', 'build') + ' [turn 2 follows after the report: What comes next?]'

foreach ($sn in ($FIX.Keys | Sort-Object)) {
  $sd = "$EV/$sn"
  foreach ($leg in @('baseline','candidate')) {
    New-Item -ItemType Directory -Force -Path "$sd/project-$leg/audits", "$sd/sess", "$sd/install-$leg", "$sd/raw", "$sd/public" | Out-Null
  }
  foreach ($f in $FIX[$sn]) {
    foreach ($leg in @('baseline','candidate')) { WU "$sd/project-$leg/$($f[0])" $f[1] }
  }
  WU "$sd/prompt.md" ($PROMPTS[$sn] + "`n")
  $sessB = 'sess-' + (Hex 4); $sessC = 'sess-' + (Hex 4)
  WU "$sd/sess-baseline.json" "{`"session`": `"$sessB`", `"scenario`": `"$sn`", `"leg`": `"baseline`", `"created_utc`": `"$NOW`"}"
  WU "$sd/sess-candidate.json" "{`"session`": `"$sessC`", `"scenario`": `"$sn`", `"leg`": `"candidate`", `"created_utc`": `"$NOW`"}"

  # install roots: baseline = extracted v0.9.4 audit surface; candidate = installed v0.9.5 skill surface
  Push-Location $WT
  foreach ($pair in @( @('plugins/sefi-core/commands/audit.md','audit.md'), @('plugins/sefi-core/agents/systems-auditor.md','systems-auditor.md'), @('docs/AUDIT-DEPARTMENTS.md','AUDIT-DEPARTMENTS.md'), @('plugins/sefi-core/scripts/ci/validate-audit-report.sh','validate-audit-report.sh') )) {
    $c = & git --no-pager show "${BASE_REV}:$($pair[0])"
    WU "$sd/install-baseline/$($pair[1])" (($c -join "`n") + "`n")
  }
  Pop-Location
  Copy-Item "$WT/plugins/sefi-core/skills/systems-audit/SKILL.md" "$sd/install-candidate/SKILL.md"
  Copy-Item "$WT/plugins/sefi-core/skills/systems-audit/references/report-contract.md" "$sd/install-candidate/report-contract.md"
  Copy-Item "$WT/plugins/sefi-core/skills/systems-audit/references/evidence-method.md" "$sd/install-candidate/evidence-method.md"
  Copy-Item "$WT/plugins/sefi-core/agents/systems-auditor.md" "$sd/install-candidate/systems-auditor.md"
  Copy-Item "$WT/plugins/sefi-core/commands/audit.md" "$sd/install-candidate/audit.md"
  Copy-Item "$WT/plugins/sefi-core/scripts/ci/prepare-audit-report-path.sh" "$sd/install-candidate/prepare-audit-report-path.sh"
  Copy-Item "$WT/plugins/sefi-core/scripts/ci/format-audit-findings.sh" "$sd/install-candidate/format-audit-findings.sh"
  Copy-Item "$WT/plugins/sefi-core/scripts/ci/validate-audit-report.sh" "$sd/install-candidate/validate-audit-report.sh"
  WU "$sd/install-baseline/runtime-manifest.json" "{`"revision`": `"$BASE_REV`", `"method`": `"git-show extraction of v0.9.4 audit surface`", `"note`": `"systems-audit skill absent at this revision (verified); supported path is /sefi:audit -> systems-auditor`"}"
  WU "$sd/install-candidate/runtime-manifest.json" "{`"revision`": `"$CAND_REV`", `"method`": `"copy of installed v0.9.5 skill surface from candidate checkout`"}"
}

# S18: deny read on required research digest in both copies; verify denial holds for SYSTEM
foreach ($leg in @('baseline','candidate')) {
  $p = "$EV/S18/project-$leg/research/digest.md"
  & icacls $p /deny 'NT AUTHORITY\SYSTEM:(R)' | Out-Null
  try { Get-Content $p -ErrorAction Stop | Out-Null; WU "$EV/S18/deny-proof-$leg.txt" "UNEXPECTED: readable" }
  catch { WU "$EV/S18/deny-proof-$leg.txt" "denied as expected: $($_.Exception.Message)" }
}
# S19: deny write on audits/ in both copies; verify
foreach ($leg in @('baseline','candidate')) {
  $d = "$EV/S18".Replace('S18','S19') + "/project-$leg/audits"
  & icacls $d /deny 'NT AUTHORITY\SYSTEM:(W,D,WDAC)' | Out-Null
  try { 'x' | Out-File "$d/probe.txt" -ErrorAction Stop; WU "$EV/S19/deny-proof-$leg.txt" "UNEXPECTED: writable" }
  catch { WU "$EV/S19/deny-proof-$leg.txt" "denied as expected: $($_.Exception.Message)" }
}
# S21: pre-existing report file at the exact chosen path per leg session
foreach ($leg in @('baseline','candidate')) {
  $sess = (Get-Content "$EV/S21/sess-$leg.json" -Raw | ConvertFrom-Json).session
  $ts = '2026-10-01-0000'
  WU "$EV/S21/project-$leg/audits/audit-report-build-$ts-$sess.md" "# Pre-existing sentinel report (not an audit product).`nDo not overwrite.`n"
}

# prerun.json per scenario: criteria, permissions, freshness, hashes (before either run)
foreach ($sn in ($FIX.Keys | Sort-Object)) {
  $sd = "$EV/$sn"
  $rec = [ordered]@{ scenario=$sn; recorded_utc=$NOW; criteria=$CRIT[$sn]; legs=@() }
  foreach ($leg in @('baseline','candidate')) {
    $files = @()
    $all = @()
    $evErr = $null
    $all = Get-ChildItem "$sd/project-$leg" -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable evErr
    if ($null -eq $all) { $all = @() }
    if ($evErr) { $files += [ordered]@{ path='<enumeration-partially-blocked-by-permissions>'; sha256='UNREADABLE-access-denied-at-prerun'; bytes=0; mtime_utc='UNKNOWN'; acl='UNKNOWN' } }
    foreach ($f in $all) {
      $rel = $f.FullName.Substring("$sd/project-$leg/".Length)
      try { $acl = ((& icacls $f.FullName 2>$null) -join '; ') } catch { $acl = 'UNKNOWN' }
      try { $h = (HashFile $f.FullName) } catch { $h = 'UNREADABLE-access-denied-at-prerun' }
      $files += [ordered]@{ path=$rel; sha256=$h; bytes=$f.Length; mtime_utc=($f.LastWriteTimeUtc.ToString('o')); acl=$acl }
    }
    $aud = "$sd/project-$leg/audits"
    try { $aacl = ((& icacls $aud 2>$null) -join '; ') } catch { $aacl = 'UNKNOWN' }
    $rev = if ($leg -eq 'baseline') { $BASE_REV } else { $CAND_REV }
    $rec.legs += [ordered]@{ leg=$leg; session=((Get-Content "$sd/sess-$leg.json" -Raw | ConvertFrom-Json).session); install_revision=$rev; files=$files; audits_acl=$aacl }
  }
  $h0 = ($rec.legs[0].files | ForEach-Object { $_.sha256 }) -join ','
  $h1 = ($rec.legs[1].files | ForEach-Object { $_.sha256 }) -join ','
  $rec['equivalent_copies'] = ($h0 -ceq $h1)
  WU "$sd/prerun.json" (($rec | ConvertTo-Json -Depth 8) + "`n")
}
# random A/B labels (private)
foreach ($sn in ($FIX.Keys | Sort-Object)) {
  $flip = Get-Random -Minimum 0 -Maximum 2
  $map = if ($flip -eq 0) { [ordered]@{ A='baseline'; B='candidate' } } else { [ordered]@{ A='candidate'; B='baseline' } }
  WU "$EV/$sn/labelmap.json" (($map | ConvertTo-Json) + "`n")
}
WU "$EV/README.md" "# Model evidence (Step 3, retrospective)`n`nIndependent retrospective baseline/candidate scenarios on isolated synthetic projects.`nBaseline: v0.9.4 peeled $BASE_REV via /sefi:audit -> systems-auditor (skill absent there; recorded without claiming older function fails). Candidate: $CAND_REV via installed Systems Audit skill.`nEach scenario: fresh project/session/install roots, equivalent synthetic copies, pre-run criteria/permissions/freshness/hashes in prerun.json. Raw outputs private in raw/; redacted behavior-identical copies in public/ as Output A/B per private labelmap.json. No producer verdict is published; a separate evaluator judges the pairs later.`nBlinding limitation: baseline reports use the v0.9.4 fenced format with AUDIT-*/STATUS labels; candidate reports use the v0.9.5 eight-heading contract. A reader can likely tell revisions apart by format.`nComparison is retrospective, not recovered pre-publication proof.`n"
echo "setup done: $((($FIX.Keys).Count)) scenarios"
