# fake_live_index.ps1 - test double for live_index.ps1. Serves the "after" fixture instead of
# talking to Tabletop Simulator, so diff_index.ps1 can be tested offline (TTS closed, no save).
# Same interface as the real thing: -Out (where to write the snapshot) and -Limit.
param(
    [string]$Out = '',
    [int]$Limit = 1200
)
# This stub is called IN-PROCESS by diff_index.ps1 (`& $LiveIndex -Out ...`), so the same rule
# as the real live_index.ps1 applies: no top-level `exit` -- it would kill the whole test run.
if ($Out -eq '') { Write-Host 'fake_live_index: -Out is required'; return 1 }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\after.csv') -Destination $Out -Force
Write-Host ("fake live index -> {0} (limit={1})" -f $Out, $Limit)
