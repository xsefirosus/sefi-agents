#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$WT = 'D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'
$EV = "$WT/state/acceptance-v095-2026-10-01/model-evidence"
foreach ($d in (Get-ChildItem "$EV/S*")) {
  $p = Join-Path $d.FullName 'prerun.json'
  if (Test-Path $p) {
    $j = Get-Content $p -Raw | ConvertFrom-Json
    $line = $j.scenario + ' equiv=' + $j.equivalent_copies + ' nB=' + $j.legs[0].files.Count + ' nC=' + $j.legs[1].files.Count
    Write-Output $line
  }
}
