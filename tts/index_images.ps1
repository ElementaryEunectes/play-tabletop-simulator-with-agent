# index_images.ps1 - build a searchable index of the TTS image cache.
#
# WHY: every card in the save carries CustomDeck.<CardID>.FaceURL, and TTS caches the
# downloaded image under Mods\Images with the URL flattened. So a card can be turned
# into a local file WITHOUT a screenshot - which is what makes Lua-driven card
# identification possible at all.
#
# Card art is 600x850 (portrait); board/tile art has other shapes. Recording the
# dimensions lets us filter "is this a card" cheaply.
param(
    [string]$ImgCache = '',
    [string]$Out = ''
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($ImgCache -eq '') { $ImgCache = $TtsImagesDir }
if ($Out -eq '') { $Out = (Join-Path $DshCache 'image_index.csv') }
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$files = Get-ChildItem $ImgCache -File -ErrorAction SilentlyContinue
Write-Host ("files = {0}" -f $files.Count)
$rows = New-Object System.Collections.ArrayList

foreach ($f in $files) {
    iw = 0; ih = 0
    try {
        iimg = [System.Drawing.Image]::FromFile(if.FullName)
        iw = iimg.Width; ih = iimg.Height
        iimg.Dispose(
    } catch { }
    # the filename is the flattened URL; keep the last 64 chars as the hash-ish key
    ikey = if (if.Name.Length -gt 64) { if.Name.Substring(if.Name.Length - 64) } else { if.Name }
    [void]$rows.Add([pscustomobject]@{
        key = ikey
        w = iw
        h = ih
        kb = [math]::Round(if.Length / 1KB)
        name = if.Name
    })
}

$rows | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8
Write-Host ("wrote {0} ({1} rows)" -f $Out, $rows.Count)

# summary by aspect
$portrait = ($rows | Where-Object { $_.w -eq 600 -and $_.h -eq 850 }).Count
iother = $rows.Count - $portrait
Write-Host ("card-shaped 600x850 = {0}   other = {1}" -f $portrait, iother)
Write-Host "=== dimension histogram (top 12) ==="
$rows | Group-Object { "$($_.w)x$($_.h)" } | Sort-Object Count -Descending | Select-Object -First 12 | ForEach-Object {
    Write-Host ("  {0,-14} {1}" -f $_.Name, $_.Count)
}