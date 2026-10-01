#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$WT = 'D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'
$EV = "$WT/state/acceptance-v095-2026-10-01/model-evidence"
foreach ($sn in @('S02','S09','S19','S21')) {
  foreach ($leg in @('baseline','candidate')) {
    Write-Output ("== " + $sn + " " + $leg + " ==")
    $root = "$EV/$sn/project-$leg"
    $items = Get-ChildItem $root -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($root.Length) }
    if ($null -eq $items) { Write-Output '(unlistable)' } else { $items | ForEach-Object { Write-Output $_ } }
  }
}
