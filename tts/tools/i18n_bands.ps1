# i18n_bands.ps1 - find the text bands in a card image, and draw a preview you can read coordinates off.
#
# See tts\docs\I18N.md section 1b. Mechanism: Get-I18nTextBands / Export-I18nBandPreview in
# tts\lib\i18nimg.ps1.
#
# WHY NOT OCR: no OCR engine exists on this machine and none can be installed here, so shipping an "OCR
# tool" would mean shipping something never run. This finds WHERE text-like detail sits (high-frequency
# rows) and hands the human a few candidate bands plus a picture with them drawn on it. It never reads
# the text - you still decide what it says and what it should say.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\i18n_bands.ps1 -Url <image url>
#   ... -Image <file>          (or point at a file directly)
#   ... -Json                  (emit ready-to-paste rule blocks instead of a table)
#   ... -GridStep 100          (draw a coordinate grid on the preview)
#
# ASCII only on purpose: no CJK here means no BOM to lose.
param(
    [string]$Root = '',
    [string]$Image = '',
    [string]$Url = '',
    [string]$ImagesDir = '',
    [string]$Out = '',
    [int]$WorkWidth = 600,
    [double]$RowEdge = 0,
    [int]$PreviewWidth = 1100,
    [int]$GridStep = 0,
    [switch]$Json
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')
. (Join-Path $Root 'tts\lib\i18nimg.ps1')

if ($ImagesDir -eq '') { $ImagesDir = $TtsImagesDir }
if ($Out -eq '') { $Out = Join-Path $DshCache 'i18n_img\bands' }
if ($Image -eq '') {
    if ($Url -eq '') { Write-Host 'ERR give -Image <file> or -Url <image url>'; exit 2 }
    $f = Find-I18nCachedImage -Dir $ImagesDir -Url $Url
    if ($null -eq $f) { Write-Host ('ERR no cached file for that url under ' + $ImagesDir); exit 2 }
    $Image = $f.FullName
}
if (-not (Test-Path -LiteralPath $Image)) { Write-Host ('ERR no such image: ' + $Image); exit 2 }
if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Force $Out | Out-Null }

$size = [System.Drawing.Image]::FromFile($Image)
$sw = [int]$size.Width
$sh = [int]$size.Height
$kb = [math]::Round((Get-Item -LiteralPath $Image).Length / 1KB, 0)
$size.Dispose()

$t0 = Get-Date
$bands = Get-I18nTextBands -Path $Image -WorkWidth $WorkWidth -RowEdge $RowEdge
$ms = [int]((Get-Date) - $t0).TotalMilliseconds

$base = [System.IO.Path]::GetFileNameWithoutExtension($Image)
if ($base.Length -gt 24) { $base = $base.Substring($base.Length - 24) }
$preview = Join-Path $Out ($base + '.bands.png')
Export-I18nBandPreview -Path $Image -OutPath $preview -Bands $bands -PreviewWidth $PreviewWidth -GridStep $GridStep

Write-Host ('image   : ' + (Split-Path $Image -Leaf))
Write-Host ('size    : ' + $sw + ' x ' + $sh + '   ' + $kb + ' KB')
Write-Host ('scanned : ' + @($bands).Count + ' band(s) in ' + $ms + ' ms   (work width ' + $WorkWidth + ', row edge ' + $RowEdge + ')')
Write-Host ('preview : ' + $preview)
Write-Host ''

if (@($bands).Count -eq 0) { Write-Host 'no text-like bands found - pass a smaller -RowEdge (e.g. 0.015 for flat art) and try again'; exit 0 }

if ($Json) {
    $blocks = foreach ($b in $bands) {
        $w = $b.x1 - $b.x0
        $h = $b.y1 - $b.y0
        '  { "match": "<url substring>", "x": ' + $b.x0 + ', "y": ' + $b.y0 + ', "w": ' + $w + ', "h": ' + $h +
        ', "fill": "#120E0C", "alpha": 240, "lines": [ { "text": "<Chinese>", "x": ' + ($b.x0 + 6) + ', "y": ' + ($b.y0 + 2) +
        ', "font": "Microsoft YaHei", "size": ' + [int][Math]::Max(12, [Math]::Round($h * 0.62)) + ', "bold": true, "color": "#FFD700" } ] }'
    }
    Write-Host '{ "blocks": ['
    Write-Host (($blocks -join ",`n"))
    Write-Host '] }'
    exit 0
}

Write-Host 'band   y range        x range          peak'
foreach ($b in $bands) {
    Write-Host ('  ' + ([string]$b.y0).PadLeft(5) + '-' + ([string]$b.y1).PadRight(6) + '  ' +
                ([string]$b.x0).PadLeft(5) + '-' + ([string]$b.x1).PadRight(6) + '  ' + $b.score)
}
Write-Host ''
Write-Host 'next    : read the preview, pick the band(s) to cover, put them in a rule file, then'
Write-Host '          tts\tools\i18n_images.ps1 -Rules <that file> [-Apply]'
