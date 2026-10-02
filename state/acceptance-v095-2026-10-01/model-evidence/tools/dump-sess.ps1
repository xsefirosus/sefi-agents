#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'
$WT = 'D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'
$EV = "$WT/state/acceptance-v095-2026-10-01/model-evidence"
$SCOPES = @{ S01='complete'; S02='research'; S03='product'; S04='design'; S05='build'; S06='quality'; S07='docs'; S08='delivery'; S10='build'; S14='complete'; S15='complete'; S16='quality'; S17='quality'; S18='complete'; S19='build'; S20='complete'; S21='build'; S22='build' }
foreach ($sn in ($SCOPES.Keys | Sort-Object)) {
  foreach ($leg in @('baseline','candidate')) {
    $sess = (Get-Content "$EV/$sn/sess-$leg.json" -Raw | ConvertFrom-Json).session
    Write-Output ($sn + ' ' + $leg + ' scope=' + $SCOPES[$sn] + ' sess=' + $sess)
  }
}
foreach ($sn in @('S09','S11','S12','S13')) {
  foreach ($leg in @('baseline','candidate')) {
    $sess = (Get-Content "$EV/$sn/sess-$leg.json" -Raw | ConvertFrom-Json).session
    Write-Output ($sn + ' ' + $leg + ' scope=- sess=' + $sess)
  }
}
