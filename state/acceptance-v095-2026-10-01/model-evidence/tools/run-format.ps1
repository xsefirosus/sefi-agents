#!/usr/bin/env pwsh
# Run the installed finding formatter over each candidate TSV (genuine supported path).
$ErrorActionPreference = 'Stop'
$WT = 'D:/Projects/Sefi-Agents/.worktrees/v095-handover-20261001'
$EV = "$WT/state/acceptance-v095-2026-10-01/model-evidence"
$GBASH = 'C:\Program Files\Git\bin\bash.exe'
function WU($path, $text) {
  $dir = Split-Path $path -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}
foreach ($sn in @('S01','S02','S03','S04','S05','S06','S07','S08','S10','S14','S16','S17','S20','S22')) {
  $rt = "$EV/$sn/install-candidate".Replace('\','/')
  $tsv = "$EV/$sn/raw/findings-candidate.tsv".Replace('\','/')
  $cmd = "LC_ALL=C.UTF-8 bash '$rt/format-audit-findings.sh' < '$tsv'"
  $out = & $GBASH -c $cmd 2>&1
  $code = $LASTEXITCODE
  WU "$EV/$sn/raw/findings-formatted.txt" (($out -join "`n") + "`n")
  WU "$EV/$sn/raw/formatter-exit.txt" ("exit=" + $code + "`n")
}
Write-Output 'format done'
