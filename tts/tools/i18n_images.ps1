# i18n_images.ps1 - patch a mod's card art in place, by rewriting TTS's own image cache.
#
# See tts\docs\I18N.md section 1b for the whole story. Mechanism is tts\lib\i18nimg.ps1.
#
# WHAT IT DOES
#   1. reads a save, collects every image URL it references
#   2. keeps the ones your rule file has blocks for, and finds each one's file in Mods\Images
#   3. redraws it (opaque block + text) into -Out, preserving pixel size exactly
#   4. with -Apply: copies the original into -Backup FIRST (never overwriting an existing backup), then
#      overwrites the cache file
#
# WHY FROM THE BACKUP: so re-running with fixed coordinates never stacks patches on top of a patch.
#
# EXPLICIT SWITCH, per repository rule: without -Apply this only reports what it would do.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\i18n_images.ps1 -Rules rules.json
#   ... -Apply
#   ... -Restore          (put every backed-up original back)
#
# ASCII only on purpose: no CJK here means no BOM to lose (Chinese text lives in the rule JSON).
param(
    [string]$Root = '',
    [string]$Save = '',
    [string]$Rules = '',
    [string]$ImagesDir = '',
    [string]$Out = '',
    [string]$Backup = '',
    [switch]$Apply,
    [switch]$Restore
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')
. (Join-Path $Root 'tts\lib\i18nimg.ps1')

if ($ImagesDir -eq '') { $ImagesDir = $TtsImagesDir }
if ($Out -eq '') { $Out = Join-Path $DshCache 'i18n_img\patch' }
if ($Backup -eq '') { $Backup = Join-Path $DshCache 'i18n_img\backup' }
if (-not (Test-Path -LiteralPath $ImagesDir)) { Write-Host ('ERR no image cache: ' + $ImagesDir); exit 2 }

# ---- restore mode -------------------------------------------------------------------------------
if ($Restore) {
    if (-not (Test-Path -LiteralPath $Backup)) { Write-Host ('nothing to restore: ' + $Backup + ' does not exist'); exit 0 }
    $files = Get-ChildItem -LiteralPath $Backup -File
    if (-not $Apply) {
        Write-Host ('REPORT ONLY (no -Apply): would restore ' + $files.Count + ' file(s) into ' + $ImagesDir)
        foreach ($f in $files) { Write-Host ('   ' + $f.Name) }
        exit 0
    }
    $n = 0
    foreach ($f in $files) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $ImagesDir $f.Name) -Force; $n++ }
    Write-Host ('restored ' + $n + ' original(s) into ' + $ImagesDir)
    Write-Host 'restart TTS for the originals to come back'
    exit 0
}

if ($Rules -eq '') { Write-Host 'ERR -Rules is required (a JSON rule file; see tts\docs\I18N.md 1b)'; exit 2 }
if (-not (Test-Path -LiteralPath $Rules)) { Write-Host ('ERR no such rule file: ' + $Rules); exit 2 }
if ($Save -eq '') {
    $newest = Get-ChildItem $TtsSavesDir -Filter 'TS_AutoSave*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $newest) { Write-Host ('ERR no TS_AutoSave*.json under ' + $TtsSavesDir); exit 2 }
    $Save = $newest.FullName
}
if (-not (Test-Path -LiteralPath $Save)) { Write-Host ('ERR no such save: ' + $Save); exit 2 }

$blocks = Get-I18nImageRule -RulePath $Rules
$raw = [System.IO.File]::ReadAllText($Save, [System.Text.Encoding]::UTF8)
$urls = Get-I18nImageUrls -Raw $raw

Write-Host ('save      : ' + (Split-Path $Save -Leaf))
Write-Host ('image dir : ' + $ImagesDir)
Write-Host ('rules     : ' + (Split-Path $Rules -Leaf) + '  (' + @($blocks).Count + ' block group(s))')
Write-Host ('urls      : ' + $urls.Count + ' distinct image url(s) in this save')
Write-Host ''

$matched = 0
$missing = 0
$skipped = 0
$plan = New-Object System.Collections.Generic.List[object]
foreach ($u in $urls.Keys) {
    $rule = @($blocks) | Where-Object { $u -like ('*' + $_.match + '*') } | Select-Object -First 1
    if ($null -eq $rule) { $skipped++; continue }
    $f = Find-I18nCachedImage -Dir $ImagesDir -Url $u
    if ($null -eq $f) { $missing++; Write-Host ('  MISSING   ' + $u.Substring([Math]::Max(0, $u.Length - 40))); continue }
    $matched++
    $plan.Add([pscustomobject]@{ url = $u; file = $f; rule = $rule })
}
Write-Host ('matched   : ' + $matched + ' url(s) have a rule   (no rule: ' + $skipped + ', cache miss: ' + $missing + ')')
Write-Host ''

if ($matched -eq 0) { Write-Host 'nothing to do'; exit 0 }
if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Force $Out | Out-Null }
if ($Apply -and -not (Test-Path -LiteralPath $Backup)) { New-Item -ItemType Directory -Force $Backup | Out-Null }

$done = New-Object System.Collections.Generic.List[object]
foreach ($p in $plan) {
    $ext = $p.file.Extension
    $target = Join-Path $Out ($p.file.BaseName + $ext)
    $src = $p.file.FullName
    $backupFile = Join-Path $Backup $p.file.Name
    # Redraw from the pristine original whenever we already have one, so repeated runs never stack.
    if (Test-Path -LiteralPath $backupFile) { $src = $backupFile }
    New-I18nPatchedImage -SourcePath $src -OutPath $target -Blocks @($p.rule)
    $before = (Get-Item -LiteralPath $p.file.FullName).Length
    $after = (Get-Item -LiteralPath $target).Length
    Write-Host ('  PATCHED   ' + $p.file.Name.Substring([Math]::Max(0, $p.file.Name.Length - 24)) +
                '   ' + [math]::Round($before / 1KB, 0) + ' KB -> ' + [math]::Round($after / 1KB, 0) + ' KB')
    if ($after -gt 1536 * 1KB) { Write-Host ('     WARN over the ~1.5 MB mark where TTS starts showing a blank tile') }
    $done.Add([pscustomobject]@{ file = $p.file.Name; backup = $backupFile; built = $target })
}

Write-Host ''
if (-not $Apply) {
    Write-Host ('REPORT ONLY (no -Apply): ' + $done.Count + ' image(s) built into ' + $Out)
    Write-Host 'nothing was written to the image cache'
    exit 0
}
$n = 0
foreach ($d in $done) {
    if (-not (Test-Path -LiteralPath $d.backup)) { Copy-Item -LiteralPath (Join-Path $ImagesDir $d.file) -Destination $d.backup -Force }
    Copy-Item -LiteralPath $d.built -Destination (Join-Path $ImagesDir $d.file) -Force
    $n++
}
Write-Host ('applied   : ' + $n + ' image(s) replaced in ' + $ImagesDir)
Write-Host ('backups   : ' + $Backup + '   (first-time only; re-runs rebuild from these)')
Write-Host 'RESTART TTS - setCustomObject on an unchanged URL does NOT reload the cache'
Write-Host ('undo      : powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\i18n_images.ps1 -Restore -Apply')
