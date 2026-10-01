#!/usr/bin/env pwsh
# Mechanical pre-write evidence gathering (no audit reasoning here).
# Runs candidate prepare-audit-report-path for every reporting scenario; records outcome.
$ErrorActionPreference = 'Stop'
$WT = 'D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'
$EV = "$WT/state/acceptance-v095-2026-10-01/model-evidence"
$GBASH = 'C:\Program Files\Git\bin\bash.exe'
$TS = '2026-10-01-0000'
$SCOPES = @{ S01='complete'; S02='research'; S03='product'; S04='design'; S05='build'; S06='quality'; S07='docs'; S08='delivery'; S10='build'; S14='complete'; S15='complete'; S16='quality'; S17='quality'; S18='complete'; S19='build'; S20='complete'; S21='build'; S22='build' }
function WU($path, $text) {
  $dir = Split-Path $path -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}
foreach ($sn in ($SCOPES.Keys | Sort-Object)) {
  $scope = $SCOPES[$sn]
  foreach ($leg in @('baseline','candidate')) {
    $sess = (Get-Content "$EV/$sn/sess-$leg.json" -Raw | ConvertFrom-Json).session
    $proj = "$EV/$sn/project-$leg"
    $rep = "$proj/audits/audit-report-$scope-$TS-$sess.md"
    if ($leg -eq 'candidate') {
      $wslProj = $proj.Replace('\','/')
      $wslRep = $rep.Replace('\','/')
      $wslRt = "$EV/$sn/install-candidate".Replace('\','/')
      $out = & $GBASH "$wslRt/prepare-audit-report-path.sh" --root $wslProj --scope $scope --report $wslRep 2>&1
      $code = $LASTEXITCODE
      WU "$EV/$sn/leg-prepare-candidate.txt" ("exit=" + $code + "`n" + (($out | Out-String)) + "`nreport=" + $rep + "`n")
    } else {
      $exists = Test-Path $rep
      WU "$EV/$sn/leg-pathcheck-baseline.txt" ("report=" + $rep + "`npre_exists=" + $exists + "`n")
    }
  }
}
# S19: genuine write-attempt evidence in the denied destination (both legs)
foreach ($leg in @('baseline','candidate')) {
  $sess = (Get-Content "$EV/S19/sess-$leg.json" -Raw | ConvertFrom-Json).session
  $rep = "$EV/S19/project-$leg/audits/audit-report-build-$TS-$sess.md"
  try { [IO.File]::WriteAllText($rep, 'probe', [Text.UTF8Encoding]::new($false)); WU "$EV/S19/leg-write-attempt-$leg.txt" "UNEXPECTED: write succeeded" }
  catch { WU "$EV/S19/leg-write-attempt-$leg.txt" ("write failed as expected: " + $_.Exception.Message + "`nreport=" + $rep + "`n") }
}
# S18: genuine read-attempt evidence on the denied artifact (both legs)
foreach ($leg in @('baseline','candidate')) {
  $p = "$EV/S18/project-$leg/research/digest.md"
  try { Get-Content $p -ErrorAction Stop | Out-Null; WU "$EV/S18/leg-read-attempt-$leg.txt" "UNEXPECTED: readable" }
  catch { WU "$EV/S18/leg-read-attempt-$leg.txt" ("read failed as expected: " + $_.Exception.Message + "`nartifact=" + $p + "`n") }
}
Write-Output 'leg exec done'
