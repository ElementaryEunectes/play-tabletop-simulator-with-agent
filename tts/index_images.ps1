# index_images.ps1 - build a searchable index of the TTS image cache.
#
# WHY: every card in the save carries CustomDeck.<CardID>.FaceURL, and TTS caches the
# downloaded image under Mods\Images with the URL flattened. So a card can be turned
# into a local file WITHOUT a screenshot - which is what makes Lua-driven card
# identification possible at all.
#
# Card art is 600x850 (portrait); board/tile art has other shapes. Recording the
# dimensions lets us filter "is this a card" cheaply.
#
# NOTE 2026-10-08: the body of this file was repaired after the batch-replace incident.
# The damage pattern was: "$" -> "i", ")" deleted, "'" -> "C", "J" deleted. Read the
# whole file before editing, and run check_ps1.ps1 afterwards.
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
    $w = 0; $h = 0
    try {
        $img = [System.Drawing.Image]::FromFile($f.FullName)
        $w = $img.Width; $h = $img.Height
        $img.Dispose()
    } catch { }
    # the filename is the flattened URL; keep the last 64 chars as the hash-ish key
    $key = if ($f.Name.Length -gt 64) { $f.Name.Substring($f.Name.Length - 64) } else { $f.Name }
    [void]$rows.Add([pscustomobject]@{
        key = $key
        w = $w
        h = $h
        kb = [math]::Round($f.Length / 1KB)
        name = $f.Name
    })
}

$rows | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8
Write-Host ("wrote {0} ({1} rows)" -f $Out, $rows.Count)

# summary by aspect
$portrait = ($rows | Where-Object { $_.w -eq 600 -and $_.h -eq 850 }).Count
$other = $rows.Count - $portrait
Write-Host ("card-shaped 600x850 = {0}   other = {1}" -f $portrait, $other)
Write-Host "=== dimension histogram (top 12) ==="
$rows | Group-Object { "$($_.w)x$($_.h)" } | Sort-Object Count -Descending | Select-Object -First 12 | ForEach-Object {
    Write-Host ("  {0,-14} {1}" -f $_.Name, $_.Count)
}
