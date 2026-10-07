# start-agent.ps1 - launch DSH with THIS folder as the project workspace.
#
# WHY THIS EXISTS
#   `$env:DSH_HOME` decides two things:
#     1. where the harness keeps its own state (sessions\, storages\, profiles\...), and
#     2. what this project's `tts\config.ps1` resolves as the workspace root
#        (cache\, out\, logs\, shots\ live there).
#   If the shell that starts dsh still has the OLD value (e.g. C:\Users\<you>\.dsh from a
#   previous layout), every script silently writes to / reads from a folder that no longer
#   exists. This launcher pins it to the folder this file lives in.
#
# USAGE (from anywhere):
#   powershell -NoProfile -ExecutionPolicy Bypass -File <project>\start-agent.ps1
#   ...then run `dsh web` (or plain `dsh`) in that same window.
#
# NOTE: param() must stay the first statement; nothing may precede it.
param(
    [switch]$NoLaunch,
    [string]$DshCommand = 'dsh web'
)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:DSH_HOME = $root
Write-Host ("DSH_HOME = " + $env:DSH_HOME)
Write-Host ("project  = " + $root)
if (-not (Test-Path (Join-Path $root 'tts\config.ps1'))) {
    Write-Host "WARN: tts\config.ps1 not found under this project root." -ForegroundColor Yellow
}
if ($NoLaunch) { Write-Host "(-NoLaunch: set the variable only; nothing started)"; return }
Write-Host ("launching: " + $DshCommand)
Set-Location -LiteralPath $root
& powershell -NoProfile -Command $DshCommand
