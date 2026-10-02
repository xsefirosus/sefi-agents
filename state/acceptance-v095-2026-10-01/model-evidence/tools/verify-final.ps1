#!/usr/bin/env pwsh
# Final verification: manifest shape, redaction, label balance, git cleanliness.
$ErrorActionPreference = 'Stop'
$WT = 'D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'
$EV = "$WT/state/acceptance-v095-2026-10-01/model-evidence"
$lines = Get-Content "$EV/manifest.jsonl"
Write-Output ("manifest lines=" + $lines.Count)
$legs = $lines | Where-Object { $_ -like '*"type":"leg"*' }
Write-Output ("leg records=" + $legs.Count)
$pend = $legs | Where-Object { $_ -like '*PENDING*' }
Write-Output ("legs mentioning PENDING=" + $pend.Count)
foreach ($sn in @('S01','S20')) {
  $m = Get-Content "$EV/$sn/labelmap.json" -Raw
  Write-Output ($sn + ' labels: ' + ($m -replace "`n",' '))
}
$pairs = @(@('S01','candidate','A'),@('S20','candidate','A'),@('S14','baseline','B'))
foreach ($t in $pairs) {
  $r = [IO.File]::ReadAllText("$EV/$($t[0])/raw/$($t[1]).md", [Text.Encoding]::UTF8)
  $p = [IO.File]::ReadAllText("$EV/$($t[0])/public/output-$($t[2]).md", [Text.Encoding]::UTF8)
  Write-Output ($t[0] + '/' + $t[1] + ' redacted-pair-identical=' + ($r.Replace($WT,'[SYNTH-ROOT]') -eq $p))
}
$nA = 0
foreach ($d in (Get-ChildItem "$EV/S*")) {
  $lp = Join-Path $d.FullName 'labelmap.json'
  if (Test-Path $lp) { if ((Get-Content $lp -Raw | ConvertFrom-Json).A -eq 'baseline') { $nA++ } }
}
Write-Output ('scenarios with A=baseline: ' + $nA + ' of 22')
Push-Location $WT
Write-Output '--- git status (first 8) ---'
git status --short | Select-Object -First 8
Write-Output '--- git log (must still be 24d348f, no new commits) ---'
git log --oneline -1
git rev-parse HEAD
Pop-Location
$total = (Get-ChildItem $EV -Recurse -File -Force -ErrorAction SilentlyContinue).Count
Write-Output ("evidence files total=" + $total)
