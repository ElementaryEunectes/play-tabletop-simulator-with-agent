# ocr_boxes.ps1 - OCR a card image, draw the recognised boxes on a preview, and emit a rule skeleton.
#
# WHY THIS REPLACES THE EYEBALL STEP: lib\i18nimg.ps1's text-band detector finds which ROWS hold detail but
# not which text is where (measured: x extent 115-2899 on a 3004-wide card - i.e. the whole image). OCR
# returns one tight box per word with a confidence, which is exactly what "cover this bit" needs. Measured
# on a real 3004x1645 card: 15 boxes, THE at (196,116) 189x99 score 0.994, QUARTERED at (419,120) 582x90
# score 0.983, DRAW/DISCARD (vertical) also found.
#
# WHY IT CALLS PYTHON DIRECTLY (`& python.exe`) AND NOT VIA A SPAWNING HELPER: PowerShell's & runs it in the
# same process tree, which the sandbox allows; it is npm/pip's internal spawning that gets EPERM.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\ocr_boxes.ps1 -Url <image url>
#   ... -Image <file>   -MinScore 0.5   -PreviewWidth 1400
#
# Outputs (under -Out, default cache\i18n_img\ocr):
#   <name>.boxes.png    preview with every box drawn and labelled
#   <name>.boxes.json   the raw boxes
#   <name>.rules.json   a rule skeleton for tts\tools\i18n_images.ps1 - one block per box, text = TODO
#
# ASCII only on purpose: no CJK here means no BOM to lose.
param(
    [string]$Root = '',
    [string]$Image = '',
    [string]$Url = '',
    [string]$ImagesDir = '',
    [string]$Out = '',
    [string]$Python = '',
    [double]$MinScore = 0.6,
    [int]$PreviewWidth = 1100
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')
. (Join-Path $Root 'tts\lib\i18nimg.ps1')

if ($ImagesDir -eq '') { $ImagesDir = $TtsImagesDir }
if ($Python -eq '') { $Python = Join-Path $Root 'local\scratch\python\python.exe' }
if (-not (Test-Path -LiteralPath $Python)) { Write-Host ('ERR python not found: ' + $Python); Write-Host 'see tts\docs\I18N.md section 2d'; exit 2 }
if ($Image -eq '') {
    if ($Url -eq '') { Write-Host 'ERR give -Image <file> or -Url <image url>'; exit 2 }
    $f = Find-I18nCachedImage -Dir $ImagesDir -Url $Url
    if ($null -eq $f) { Write-Host ('ERR no cached file for that url under ' + $ImagesDir); exit 2 }
    $Image = $f.FullName
}
if (-not (Test-Path -LiteralPath $Image)) { Write-Host ('ERR no such image: ' + $Image); exit 2 }
if ($Out -eq '') { $Out = Join-Path $DshCache 'i18n_img\ocr' }
if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Force $Out | Out-Null }

$probe = Join-Path $Root 'tts\tools\ocr_probe.py'
if (-not (Test-Path -LiteralPath $probe)) { Write-Host ('ERR missing ' + $probe); exit 2 }

$tmpDir = Join-Path $DshCache 'pytmp'
if (-not (Test-Path -LiteralPath $tmpDir)) { New-Item -ItemType Directory -Force $tmpDir | Out-Null }
$env:TMP = $tmpDir
$env:TEMP = $tmpDir
$env:PYTHONIOENCODING = 'utf-8'

Write-Host ('image  : ' + (Split-Path $Image -Leaf))
$json = & $Python $probe $Image --json 2>&1
$code = $LASTEXITCODE
# The probe prints "model loaded in ..." before the JSON, so start at the first bracket.
$text = ($json | Out-String)
$start = $text.IndexOf('[')
if ($start -lt 0) { Write-Host 'ERR the OCR probe produced no JSON:'; Write-Host $text; exit 3 }
$boxes = ($text.Substring($start) | ConvertFrom-Json)
if ($code -ne 0) { Write-Host ('WARN probe exit ' + $code) }

$kept = @($boxes | Where-Object { $_.score -ge $MinScore })
Write-Host ('boxes  : ' + @($boxes).Count + ' raw, ' + $kept.Count + ' above score ' + $MinScore)

$base = [System.IO.Path]::GetFileNameWithoutExtension($Image)
if ($base.Length -gt 24) { $base = $base.Substring($base.Length - 24) }

$preview = Join-Path $Out ($base + '.boxes.png')
Export-I18nBandPreview -Path $Image -OutPath $preview -Bands $kept -PreviewWidth $PreviewWidth
Write-Host ('preview: ' + $preview)

$boxesPath = Join-Path $Out ($base + '.boxes.json')
[System.IO.File]::WriteAllText($boxesPath, ($kept | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

# Rule skeleton: one block per box, sized exactly to the box. The Chinese is left as TODO on purpose -
# deciding what a term should say is a human call (see tts\i18n\terms_card.tsv for how that goes).
$skeleton = $kept | ForEach-Object {
    $h = $_.y1 - $_.y0
    [ordered]@{
        match = '<url substring>'
        x     = $_.x0
        y     = $_.y0
        w     = $_.x1 - $_.x0
        h     = $h
        fill  = '#120E0C'
        alpha = 240
        lines = @([ordered]@{
                text  = 'TODO: ' + $_.text
                x     = $_.x0 + 4
                y     = $_.y0 + 2
                font  = 'Microsoft YaHei'
                size  = [int][Math]::Max(12, [Math]::Round($h * 0.62))
                bold  = $true
                color = '#FFD700'
            })
    }
}
$rulesPath = Join-Path $Out ($base + '.rules.json')
[System.IO.File]::WriteAllText($rulesPath, (@{ blocks = $skeleton } | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('rules  : ' + $rulesPath)
Write-Host ''
Write-Host 'next   : read the preview, replace each TODO with the Chinese, set match, then'
Write-Host '         tts\tools\i18n_images.ps1 -Rules <that file> [-Apply]'
