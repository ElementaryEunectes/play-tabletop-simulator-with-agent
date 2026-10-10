# turn_side.ps1 - whose turn is it right now, read from the mod's ONE-TIME calibration.
#
# WHY: seat coordinates differ per mod, so this cannot be hardcoded. cache\<game>_turn.json is the
# single source of truth (written by tts\tools\turn_calib.ps1, together with the evidence that settled
# it). This script only MEASURES and COMPARES - it never infers which side is which.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\turn_side.ps1
#   prints exactly one of: mine | player | unknown | uncalibrated
#
# ⛔ Do NOT re-derive the mapping from coordinates, screen direction or logs - I did that twice and was
# wrong twice. If the judgement is ever wrong, the fix is to re-run turn_calib.ps1 with a fresh press,
# not to edit numbers here.
param(
    [string]$Root = '',
    [string]$Game = ''
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')
if ($Game -eq '') { $Game = $DshGame }
if ($Game -eq '') { Write-Output 'uncalibrated'; return }
$calibFile = Join-Path $DshCache ($Game + '_turn.json')
if (-not (Test-Path -LiteralPath $calibFile)) { Write-Output 'uncalibrated'; return }
$doc = [System.IO.File]::ReadAllText($calibFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

$raw = $null
# In-process transport first: one PowerShell process instead of two.
#
# Measured 2026-10-11: spawning a child `powershell ... ds.ps1` made this script 1028 ms, and the turn
# poller runs it every 2.5 s - a 40% duty cycle for a single position read. The generic transport in
# tts\ttslib.ps1 + tts\lib\bridge.ps1 talks to TTS in this same process (that is how play.ps1's generic
# status works), which removes the second process start. Fall back to the child call if the libs are
# unavailable, so this script never becomes less reliable than it was.
$usedFast = $false
try {
    . (Join-Path $Root 'tts\ttslib.ps1')
    . (Join-Path $Root 'tts\lib\bridge.ps1')
    # bridge.ps1 calls Fail/Err-Code only on a HARD error (no -Soft); define them so a future edit that
    # drops -Soft still fails loudly instead of hitting a missing function.
    if (-not (Get-Command Fail -ErrorAction SilentlyContinue)) { function Fail($c, $m) { throw ("$c $m") } }
    if (-not (Get-Command Err-Code -ErrorAction SilentlyContinue)) { function Err-Code($e) { return 'BAD DATA' } }
    # turn_tracker gives the tracker's position directly (bridge v15+). Its own `side` label is NOT used:
    # the calibration file is the single decider for "whose turn" (see the header). The guid is passed
    # FROM that file so the piece we read is the piece tr.ps1 moves (the bridge constant is a fallback
    # only) - measured 2026-10-11.
    $tt = Bridge @{ cmd = 'turn_tracker'; guid = [string]$doc.tracker } -Soft
    if ($null -ne $tt -and [string]$tt.ok -eq 'True') { $z = [double]$tt.z; $usedFast = $true }
} catch { $z = $null }

if (-not $usedFast) {
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tts\ds.ps1') -Do 'index:250' -Raw 2>&1 | Out-String
    if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
    $z = $null
    try {
        $items = ($raw | ConvertFrom-Json).customMessage.items
        if ($items -is [string]) { $items = $items | ConvertFrom-Json }
        $hit = $items | Where-Object { $_.guid -eq $doc.tracker } | Select-Object -First 1
        if ($hit) { $z = [double]$hit.z }
    } catch { Write-Output 'unknown'; return }
}
if ($null -eq $z) { Write-Output 'unknown'; return }          # tracker not on the table

if ($null -eq $doc.zMine -or [string]$doc.zMine -eq '') { Write-Output 'uncalibrated'; return }
if ([math]::Abs($z - [double]$doc.zMine) -le $doc.tolerance) { Write-Output 'mine' }
elseif ($null -ne $doc.zPlayer -and [math]::Abs($z - [double]$doc.zPlayer) -le $doc.tolerance) { Write-Output 'player' }
else { Write-Output 'unknown' }                                # drifted away from both resting places
