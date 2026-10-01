#!/usr/bin/env pwsh
# Finalize: validate, verify, assemble raw transcripts + redacted public pairs + manifest.
$ErrorActionPreference = 'Stop'
$WT = 'D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'
$EV = "$WT/state/acceptance-v095-2026-10-01/model-evidence"
$GBASH = 'C:\Program Files\Git\bin\bash.exe'
$TS = '2026-10-01-0000'
$NOW = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$MODEL = 'muse-spark-1.3-contributor-free (provider opencode; session Muse Spark 1.3 Free)'
$BASE_REV = 'db5293602a0a795bddde0e618d1732a6ce1c5d64'
$CAND_REV = '24d348fb06a5100ed76cf9feff2c4d4df8922156'
$fail = 0
function WU($path, $text) {
  $dir = Split-Path $path -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}
function HF($p) { (Get-FileHash -Algorithm SHA256 -Path $p).Hash.ToLower() }
function Sect($text, $name, $next) {
  $lines = $text -split "`n"
  $cap = $false; $out = @()
  foreach ($l in $lines) {
    if ($l -eq $name) { $cap = $true; continue }
    if ($cap -and $l.StartsWith('## ')) { break }
    if ($cap) { $out += $l }
  }
  (($out -join "`n").Trim() + "`n")
}
$WITH_REPORT = @('S01','S02','S03','S04','S05','S06','S07','S08','S10','S14','S15','S16','S17','S18','S20','S22')
$SCOPES = @{ S01='complete'; S02='research'; S03='product'; S04='design'; S05='build'; S06='quality'; S07='docs'; S08='delivery'; S10='build'; S14='complete'; S15='complete'; S16='quality'; S17='quality'; S18='complete'; S19='build'; S20='complete'; S21='build'; S22='build' }
$INVOC = @{ baseline='AUDIT-VIA-SEFI-AUDIT-COMMAND (v0.9.4 agent path; skill absent)'; candidate='AUDIT-VIA-SYSTEMS-AUDIT-SKILL (SKILL.md plus evidence-method plus report contract)' }
$manifest = @()
$manifest += (@{ type='run'; finalized_utc=$NOW; baseline_revision=$BASE_REV; candidate_revision=$CAND_REV; model=$MODEL; effort='UNKNOWN (no model-for.sh envelope in this direct subagent dispatch)'; route='direct-subagent-dispatch; no per-dispatch telemetry available to producer; spend UNKNOWN'; checkout='D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'; repeats='none'; pending_legs='none (all 44 legs executed; model access available)' } | ConvertTo-Json -Compress)

$scenarios = @('S01','S02','S03','S04','S05','S06','S07','S08','S09','S10','S11','S12','S13','S14','S15','S16','S17','S18','S19','S20','S21','S22')
foreach ($sn in $scenarios) {
  $sd = "$EV/$sn"
  $labelmap = Get-Content "$sd/labelmap.json" -Raw | ConvertFrom-Json
  foreach ($leg in @('baseline','candidate')) {
    $sess = (Get-Content "$sd/sess-$leg.json" -Raw | ConvertFrom-Json).session
    $proj = "$sd/project-$leg"
    $inv = $INVOC[$leg]
    $rev = if ($leg -eq 'baseline') { $BASE_REV } else { $CAND_REV }
    $pub = if ($labelmap.A -eq $leg) { 'A' } else { 'B' }
    $scope = $SCOPES[$sn]
    $repName = if ($null -ne $scope) { "audit-report-$scope-$TS-$sess.md" } else { $null }
    $repPath = if ($null -ne $repName) { "$proj/audits/$repName" } else { $null }
    $hasReport = ($WITH_REPORT -contains $sn) -and ($null -ne $repPath) -and (Test-Path $repPath)

    # 1. validator leg.
    # Candidate: installed validator with explicit --root (supported path).
    # Baseline v0.9.4: installed validator has NO --root flag; ROOT is derived
    # from the script location, so an isolated project root cannot be validated
    # as-installed. Record three genuine outcomes: (i) as-installed no-args run,
    # (ii) as-installed positional-path run, (iii) shape-only run of the
    # UNMODIFIED validator bytes relocated so ROOT covers a temp audits/ dir.
    $valOut = ''; $valExit = 'n/a'
    if ($hasReport -and ($leg -eq 'candidate')) {
      $rt = "$sd/install-$leg".Replace('\','/')
      $wProj = $proj.Replace('\','/'); $wRep = $repPath.Replace('\','/')
      $o = & $GBASH "$rt/validate-audit-report.sh" --root $wProj $wRep 2>&1
      $valExit = $LASTEXITCODE; $valOut = ($o -join "`n")
      WU "$sd/raw/validation-$leg.txt" ("exit=" + $valExit + "`n" + $valOut + "`n")
      if ($valExit -ne 0) { Write-Output ("FAIL validator candidate " + $sn); $fail++ }
    }
    if ($hasReport -and ($leg -eq 'baseline')) {
      $rt = "$sd/install-$leg".Replace('\','/')
      $wRep = $repPath.Replace('\','/')
      $log = @()
      $a = & $GBASH "$rt/validate-audit-report.sh" 2>&1
      $log += ('as-installed no-args: exit=' + $LASTEXITCODE + ' :: ' + (($a | Out-String).Trim()))
      $b = & $GBASH "$rt/validate-audit-report.sh" $wRep 2>&1
      $log += ('as-installed positional report path: exit=' + $LASTEXITCODE + ' :: ' + (($b | Out-String).Trim()))
      $t = 'C:\Windows\Temp\sefi-shape-' + $sn + '-baseline'
      if (Test-Path $t) { Remove-Item $t -Recurse -Force }
      New-Item -ItemType Directory -Force -Path "$t/a/b/c/d", "$t/audits" | Out-Null
      Copy-Item "$sd/install-baseline/validate-audit-report.sh" "$t/a/b/c/d/validate-audit-report.sh"
      Copy-Item $repPath "$t/audits/"
      $wTrep = ("$t/audits/" + $repName).Replace('\','/')
      $wTsh = ("$t/a/b/c/d/validate-audit-report.sh").Replace('\','/')
      $c = & $GBASH $wTsh $wTrep 2>&1
      $log += ('relocated shape-only run (unmodified bytes, sha=' + (HF "$sd/install-baseline/validate-audit-report.sh") + '): exit=' + $LASTEXITCODE + ' :: ' + (($c | Out-String).Trim()))
      Remove-Item $t -Recurse -Force
      $valOut = ($log -join "`n"); $valExit = 'recorded-as-discovery'
      WU "$sd/raw/validation-$leg.txt" ($valOut + "`n")
    }

    # 2. formatter-fidelity check (candidate reports with TSV rows)
    if (($leg -eq 'candidate') -and (Test-Path "$sd/raw/findings-candidate.tsv") -and $hasReport) {
      $repText = [IO.File]::ReadAllText($repPath, [Text.Encoding]::UTF8)
      $found = Sect $repText '## Findings' '## Fixes'
      $expected = [IO.File]::ReadAllText("$sd/raw/findings-formatted.txt", [Text.Encoding]::UTF8)
      if ($found -ne $expected) { Write-Output ("FAIL findings-fidelity " + $sn); $fail++ }
    }
    if ((($sn -eq 'S15') -and ($leg -eq 'candidate') -and $hasReport)) {
      $repText = [IO.File]::ReadAllText($repPath, [Text.Encoding]::UTF8)
      $found = Sect $repText '## Findings' '## Fixes'
      if ($found.Trim() -ne 'No findings in inspected surfaces.') { Write-Output ("FAIL clean-phrase " + $sn + ' ' + $leg); $fail++ }
    }

    # 3. collect transcript parts
    $parts = @()
    $parts += ('# Step 3 leg transcript: ' + $sn + ' / ' + $leg)
    $parts += ('revision=' + $rev)
    $parts += ('invocation=' + $inv)
    $parts += ('session=' + $sess)
    $parts += ('prompt_sha256=' + (HF "$sd/prompt.md"))
    if ((($leg -eq 'candidate') -and (Test-Path "$sd/leg-prepare-candidate.txt")) -or (($leg -eq 'baseline') -and (Test-Path "$sd/leg-pathcheck-baseline.txt"))) { $parts += '--- prepare/pathcheck ---'; }
    $extra = @()
    if ($leg -eq 'candidate' -and (Test-Path "$sd/leg-prepare-candidate.txt")) { $extra += [IO.File]::ReadAllText("$sd/leg-prepare-candidate.txt", [Text.Encoding]::UTF8).Trim() }
    if ($leg -eq 'baseline' -and (Test-Path "$sd/leg-pathcheck-baseline.txt")) { $extra += [IO.File]::ReadAllText("$sd/leg-pathcheck-baseline.txt", [Text.Encoding]::UTF8).Trim() }
    foreach ($f in @("$sd/raw/reply-$leg.txt","$sd/raw/dialogue-$leg.md","$sd/raw/route-$leg.md","$sd/raw/escalation-$leg.md","$sd/raw/incomplete-$leg.md","$sd/raw/refused-$leg.md","$sd/raw/turn2-$leg.md")) {
      if (Test-Path $f) { $extra += ('--- ' + (Split-Path $f -Leaf) + ' ---'); $extra += [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8).Trim() }
    }
    if ($leg -eq 'candidate' -and (Test-Path "$sd/raw/formatter-exit.txt")) { $extra += ('formatter ' + ([IO.File]::ReadAllText("$sd/raw/formatter-exit.txt", [Text.Encoding]::UTF8).Trim())) }
    if (Test-Path "$sd/raw/validation-$leg.txt") { $extra += '--- validation ---'; $extra += [IO.File]::ReadAllText("$sd/raw/validation-$leg.txt", [Text.Encoding]::UTF8).Trim() }
    if ($hasReport) {
      $extra += ('--- report file: audits/' + $repName + ' ---')
      $extra += [IO.File]::ReadAllText($repPath, [Text.Encoding]::UTF8).Trim()
      $repSha = HF $repPath
      $repMtime = (Get-Item $repPath).LastWriteTimeUtc.ToString('o')
    } else { $repSha = $null; $repMtime = $null }
    $parts += $extra
    $transcript = ($parts -join "`n") + "`n"
    WU "$sd/raw/$leg.md" $transcript

    # 4. redacted public copy
    $public = $transcript.Replace($WT, '[SYNTH-ROOT]').Replace('D:\Projects\Sefi-Agents\.worktrees\v095-handover-20261001', '[SYNTH-ROOT]')
    WU "$sd/public/output-$pub.md" $public

    $manifest += (@{ type='leg'; scenario=$sn; leg=$leg; public_label=$pub; install_revision=$rev; model=$MODEL; effort='UNKNOWN'; route='direct-subagent-dispatch'; session=$sess; report_sha256=$repSha; report_mtime_utc=$repMtime; raw_sha256=(HF "$sd/raw/$leg.md"); public_sha256=(HF "$sd/public/output-$pub.md"); validator_exit=$valExit; utc=$NOW } | ConvertTo-Json -Compress)
  }
  # scenario-level: S21 hash equality, S19 emptiness, fixture equivalence recheck
  if ($sn -eq 'S21') {
    foreach ($leg in @('baseline','candidate')) {
      $sess = (Get-Content "$sd/sess-$leg.json" -Raw | ConvertFrom-Json).session
      $f = Get-ChildItem "$sd/project-$leg/audits/audit-report-*.md"
      $pre = (Get-Content "$sd/prerun.json" -Raw | ConvertFrom-Json).legs | Where-Object { $_.leg -eq $leg }
      $preHash = ($pre.files | Where-Object { $_.path -like 'audits?*' }).sha256
      $postHash = HF $f.FullName
      if ($preHash -ne $postHash) { Write-Output ("FAIL s21-hash " + $leg); $fail++ }
      if ((Get-ChildItem "$sd/project-$leg/audits/audit-report-*.md").Count -ne 1) { Write-Output ("FAIL s21-count " + $leg); $fail++ }
    }
  }
  if ($sn -eq 'S19') {
    foreach ($leg in @('baseline','candidate')) {
      $n = @(Get-ChildItem "$sd/project-$leg/audits" -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'audit-report-*' }).Count
      if ($n -ne 0) { Write-Output ("FAIL s19-empty " + $leg); $fail++ }
    }
  }
}
WU "$EV/manifest.jsonl" (($manifest -join "`n") + "`n")
Write-Output ("finalize done, failures=" + $fail)
