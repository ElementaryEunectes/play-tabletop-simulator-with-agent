# i18n_export.ps1 - pull the translatable TEXT fields out of a TTS save into a TSV for a translator.
#
# Thin CLI wrapper: the mechanism is tts\lib\i18n.ps1 (see tts\docs\I18N.md for the contract). Keeping
# the logic there is what lets tts\tests\test_i18n.ps1 call it directly instead of spawning a PowerShell
# child - this sandbox blocks powershell.exe descendants, and an `exit` here would take a dot-sourcing
# test process down with it.
#
# CONTRACT (the only one): translator in  = id <TAB> field <TAB> source
#                           translator out = id <TAB> field <TAB> target   (empty target = keep source)
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\i18n_export.ps1 -Save <save.json> -Out <text.tsv>
#
# ASCII only on purpose: no CJK here means no BOM to lose.
param(
    [string]$Root = '',
    [string]$Save = '',
    [string]$Out = '',
    [string[]]$Fields = @('Nickname', 'Description', 'GMNotes')
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')
. (Join-Path $Root 'tts\lib\i18n.ps1')

if ($Save -eq '') {
    $newest = Get-ChildItem $TtsSavesDir -Filter 'TS_AutoSave*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $newest) { Write-Host ('ERR no TS_AutoSave*.json under ' + $TtsSavesDir); exit 2 }
    $Save = $newest.FullName
}
if (-not (Test-Path -LiteralPath $Save)) { Write-Host ('ERR no such save: ' + $Save); exit 2 }
if ($Out -eq '') { $Out = Join-Path $DshCache 'i18n_text.tsv' }

$raw = [System.IO.File]::ReadAllText($Save, [System.Text.Encoding]::UTF8)
$matches = Get-I18nMatch -Raw $raw -Fields $Fields
$lines = Get-I18nTsvLines -SaveName (Split-Path -Leaf $Save) -Matches $matches

$outDir = Split-Path -Parent $Out
if ($outDir -ne '' -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }
# UTF-8 WITHOUT a BOM: a BOM would arrive as a stray character in front of the first value for most
# translators. Editors that need a BOM can be told to use UTF-8 explicitly.
[System.IO.File]::WriteAllLines($Out, $lines, (New-Object System.Text.UTF8Encoding($false)))

$nonEmpty = @($matches | Where-Object { $_.Groups[2].Value -ne '' }).Count
Write-Host ('save     : ' + (Split-Path $Save -Leaf) + '   ' + ('{0:N0}' -f $raw.Length) + ' bytes')
Write-Host ('fields   : ' + ($Fields -join ', '))
Write-Host ('matched  : ' + $matches.Count + '  (' + $nonEmpty + ' non-empty)')
Write-Host ('wrote    : ' + $Out)
Write-Host 'next     : have a translator fill column 4, then i18n_apply.ps1'
