# i18nimg.ps1 - the image half of the localisation mechanism (see tts\docs\I18N.md section 1b).
#
# WHY IT LIVES HERE AND NOT IN THE TOOL: same reason as lib\i18n.ps1 - the offline gate must not spawn a
# PowerShell child, so the test dot-sources these functions and calls them directly. The tool
# (tts\tools\i18n_images.ps1) only does arguments, explicit switches and I/O.
#
# THE TRICK THIS RELIES ON (measured 2026-10-13): TTS caches every image it has ever loaded under
# Mods\Images, and the cache file name is the ORIGINAL URL with every non-alphanumeric character removed
# (extension kept). So the original art is already on disk, and replacing that file replaces what the
# game shows - no download, no image host, no HTTP service, and no re-baking the save.
#
# ASCII only on purpose: no CJK here means no BOM to lose. (Text to draw arrives from a JSON rule file.)
Add-Type -AssemblyName System.Drawing

function Get-I18nImageCacheBase {
    # URL -> the cache file's base name (TTS strips everything that is not [A-Za-z0-9]).
    param([string]$Url)
    return ($Url -replace '[^A-Za-z0-9]', '')
}

function Find-I18nCachedImage {
    # The cached file for a URL, or $null. Matched on the BASE name so any extension works.
    param([string]$Dir, [string]$Url)
    $base = Get-I18nImageCacheBase -Url $Url
    if ($base -eq '') { return $null }
    return (Get-ChildItem -LiteralPath $Dir -File | Where-Object { $_.BaseName -eq $base } | Select-Object -First 1)
}

function Get-I18nImageUrls {
    # Every image URL a save references, plus how many times. A save mentions the same URL once per card,
    # so the count is also "how many objects this patch would touch" - useful when reporting.
    param([string]$Raw)
    $fields = @('FaceURL', 'BackURL', 'ImageURL', 'CustomImage', 'MeshURL', 'DiffuseURL')
    $counts = @{}
    foreach ($f in $fields) {
        foreach ($m in [regex]::Matches($Raw, '"' + $f + '"\s*:\s*"([^"]+)"')) {
            $u = $m.Groups[1].Value
            if ($u -eq '') { continue }
            if ($counts.ContainsKey($u)) { $counts[$u]++ } else { $counts[$u] = 1 }
        }
    }
    return $counts
}

function New-I18nPatchedImage {
    # Draw the patch: for each block, an opaque-ish rectangle then its text lines. Nothing else in the
    # image is touched, and the pixel size is preserved exactly (a size change is itself a way to break
    # rendering - see the size cliff in I18N.md section 1b).
    #   blocks: @( @{ x=..; y=..; w=..; h=..; fill='#120E0C'; alpha=240; lines=@(
    #                   @{ text='..'; x=..; y=..; size=60; bold=$true; color='#FFD700' } ) } )
    param(
        [string]$SourcePath,
        [string]$OutPath,
        $Blocks,
        [int]$JpegQuality = 88
    )
    $img = [System.Drawing.Image]::FromFile($SourcePath)
    try {
        $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height)
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.DrawImage($img, 0, 0, $img.Width, $img.Height)
                $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
                foreach ($b in $Blocks) {
                    $alpha = 240
                    if ($b.ContainsKey('alpha')) { $alpha = [int]$b.alpha }
                    $fill = [System.Drawing.ColorTranslator]::FromHtml($b.fill)
                    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($alpha, $fill.R, $fill.G, $fill.B))
                    $g.FillRectangle($brush, [int]$b.x, [int]$b.y, [int]$b.w, [int]$b.h)
                    $brush.Dispose()
                    foreach ($ln in $b.lines) {
                        $style = [System.Drawing.FontStyle]::Regular
                        if ($ln.ContainsKey('bold') -and $ln.bold) { $style = [System.Drawing.FontStyle]::Bold }
                        $font = New-Object System.Drawing.Font($ln.font, [single]$ln.size, $style)
                        $col = [System.Drawing.ColorTranslator]::FromHtml($ln.color)
                        $tb = New-Object System.Drawing.SolidBrush($col)
                        $g.DrawString($ln.text, $font, $tb, [single]$ln.x, [single]$ln.y)
                        $tb.Dispose()
                        $font.Dispose()
                    }
                }
            } finally { $g.Dispose() }
            $ext = [System.IO.Path]::GetExtension($OutPath).ToLowerInvariant()
            if ($ext -eq '.png') {
                $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
            } else {
                $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
                $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
                $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [int64]$JpegQuality)
                $bmp.Save($OutPath, $codec, $ep)
            }
        } finally { $bmp.Dispose() }
    } finally { $img.Dispose() }
}

function Get-I18nImageRule {
    # Rules come from a JSON file so the Chinese text never lives in a .ps1 (that is what keeps this file
    # ASCII, and what keeps the BOM problem away). Structure:
    #   { "blocks": [ { "match": "<substring of the URL>", "x":.., "y":.., "w":.., "h":..,
    #                   "lines": [ { "text":"..", "x":.., "y":.., "size":60, "bold":true, "color":"#FFD700" } ] } ] }
    param([string]$RulePath)
    $json = [System.IO.File]::ReadAllText($RulePath, [System.Text.Encoding]::UTF8)
    $obj = $json | ConvertFrom-Json
    return $obj.blocks
}
