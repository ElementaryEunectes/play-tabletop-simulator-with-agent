# fake_live_index.ps1 - test double for live_index.ps1. Serves the "after" fixture instead of
# talking to Tabletop Simulator, so diff_index.ps1 can be tested offline (TTS closed, no save).
# Same interface as the real thing: -Out (where to write the snapshot) and -Limit.
param(
    [string]$Out = '',
    [int]$Limit = 1200
)
if ($Out -eq '') { Write-Host 'fake_live_index: -Out is required'; exit 1 }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\after.csv') -Destination $Out -Force
Write-Host ("fake live index -> {0} (limit={1})" -f $Out, $Limit)
