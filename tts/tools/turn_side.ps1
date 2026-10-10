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

$raw = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tts\ds.ps1') -Do 'index:250' -Raw 2>&1 | Out-String
if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
$z = $null
try {
    $items = ($raw | ConvertFrom-Json).customMessage.items
    if ($items -is [string]) { $items = $items | ConvertFrom-Json }
    $hit = $items | Where-Object { $_.guid -eq $doc.tracker } | Select-Object -First 1
    if ($hit) { $z = [double]$hit.z }
} catch { Write-Output 'unknown'; return }
if ($null -eq $z) { Write-Output 'unknown'; return }          # tracker not on the table

if ($null -eq $doc.zMine -or [string]$doc.zMine -eq '') { Write-Output 'uncalibrated'; return }
if ([math]::Abs($z - [double]$doc.zMine) -le $doc.tolerance) { Write-Output 'mine' }
elseif ($null -ne $doc.zPlayer -and [math]::Abs($z - [double]$doc.zPlayer) -le $doc.tolerance) { Write-Output 'player' }
else { Write-Output 'unknown' }                                # drifted away from both resting places
