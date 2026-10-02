#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$WT = 'D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'
$EV = "$WT/state/acceptance-v095-2026-10-01/model-evidence"
foreach ($sn in @('S02','S09','S19','S21','S01')) {
  foreach ($leg in @('baseline','candidate')) {
    Write-Output ("== " + $sn + " " + $leg + " ==")
    $root = "$EV/$sn/project-$leg"
    $items = Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { ("F:" + $_.FullName.Substring($root.Length).Replace('\','/')) }
    if ($null -eq $items) { Write-Output '(no files / unlistable)' } else { $items | ForEach-Object { Write-Output $_ } }
  }
}
