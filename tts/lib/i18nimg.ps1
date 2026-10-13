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

function Get-I18nTextBands {
    # Find the horizontal BANDS that contain text-like detail, without any OCR engine.
    # WHY THIS AND NOT OCR: this machine has no OCR (no tesseract, no paddle, nothing installable), and
    # a tool that cannot be tested here has no business being shipped. This does the part that is
    # testable and still useful: text is high-frequency detail, so a row that crosses glyphs has a much
    # higher neighbour-difference score than flat art. It does NOT read anything - it narrows "where"
    # down to a few bands, and a human confirms which one to cover.
    # Returns @( @{ y0; y1; x0; x1; score } ) in SOURCE pixel coordinates (bands are found on a
    # downscaled copy for speed, then scaled back up).
    param(
        [string]$Path,
        [int]$WorkWidth = 600,      # downscale target: GetPixel in a PowerShell loop is slow, ~600 px is seconds
        [double]$RowEdge = 0,       # 0 = auto (median x 1.8). MEASURED 2026-10-13: a fixed 0.12 found
                                    # NOTHING on a real 3004x1645 card - photographic art averages ~0.03,
                                    # so a fixed cut needs per-family calibration; relative to the image's
                                    # own median works across art styles.
        [int]$MinBand = 4,          # ignore bands thinner than this (in working pixels)
        [int]$Gap = 2               # rows this close belong to the same band
    )
    $src = New-Object System.Drawing.Bitmap($Path)
    try {
        $w = [int][Math]::Min($WorkWidth, $src.Width)
        $sc = $w / [double]$src.Width
        $h = [int][Math]::Max(1, [Math]::Round($src.Height * $sc))
        $small = New-Object System.Drawing.Bitmap($w, $h)
        try {
            $g = [System.Drawing.Graphics]::FromImage($small)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.DrawImage($src, 0, 0, $w, $h)
            $g.Dispose()

            # per-row edge score, and per-row first/last "busy" column (for the x extent)
            $score = New-Object 'double[]' $h
            $firstX = New-Object 'int[]' $h
            $lastX = New-Object 'int[]' $h
            for ($y = 0; $y -lt $h; $y++) {
                $sum = 0.0
                $f = -1
                $l = -1
                for ($x = 1; $x -lt $w; $x++) {
                    $a = $small.GetPixel($x, $y)
                    $b = $small.GetPixel($x - 1, $y)
                    $d = [Math]::Abs($a.R - $b.R) + [Math]::Abs($a.G - $b.G) + [Math]::Abs($a.B - $b.B)
                    $sum += $d
                    if ($d -gt 90) { if ($f -lt 0) { $f = $x }; $l = $x }
                }
                $score[$y] = $sum / (($w - 1) * 765.0)
                $firstX[$y] = $f
                $lastX[$y] = $l
            }

            # group consecutive "busy" rows into bands
            $sorted = @($score | Sort-Object)
            $median = 0.0
            if ($sorted.Count -gt 0) { $median = $sorted[[int][Math]::Floor($sorted.Count / 2)] }
            $cut = $RowEdge
            if ($cut -le 0) { $cut = [Math]::Max(0.005, $median * 1.8) }
            $bands = New-Object System.Collections.Generic.List[object]
            $start = -1
            $lastBusy = -1
            for ($y = 0; $y -lt $h; $y++) {
                $busy = $score[$y] -ge $cut
                if ($busy) {
                    if ($start -lt 0) { $start = $y }
                    $lastBusy = $y
                } elseif ($start -ge 0 -and ($y - $lastBusy) -gt $Gap) {
                    if (($lastBusy - $start + 1) -ge $MinBand) {
                        $bands.Add([pscustomobject]@{ y0 = $start; y1 = $lastBusy })
                    }
                    $start = -1
                }
            }
            if ($start -ge 0 -and ($lastBusy - $start + 1) -ge $MinBand) {
                $bands.Add([pscustomobject]@{ y0 = $start; y1 = $lastBusy })
            }

            # x extent per band, and scale everything back to source pixels
            $out = New-Object System.Collections.Generic.List[object]
            $inv = if ($sc -gt 0) { 1.0 / $sc } else { 1.0 }
            foreach ($b in $bands) {
                $x0 = $w; $x1 = -1; $peak = 0.0
                for ($y = $b.y0; $y -le $b.y1; $y++) {
                    if ($firstX[$y] -ge 0 -and $firstX[$y] -lt $x0) { $x0 = $firstX[$y] }
                    if ($lastX[$y] -gt $x1) { $x1 = $lastX[$y] }
                    if ($score[$y] -gt $peak) { $peak = $score[$y] }
                }
                if ($x1 -lt $x0) { $x0 = 0; $x1 = $w - 1 }
                $out.Add([pscustomobject]@{
                    y0    = [int][Math]::Floor($b.y0 * $inv)
                    y1    = [int][Math]::Ceiling(($b.y1 + 1) * $inv)
                    x0    = [int][Math]::Floor($x0 * $inv)
                    x1    = [int][Math]::Ceiling(($x1 + 1) * $inv)
                    score = [Math]::Round($peak, 3)
                    cut   = [Math]::Round($cut, 4)
                    median = [Math]::Round($median, 4)
                })
            }
            return $out
        } finally { $small.Dispose() }
    } finally { $src.Dispose() }
}

function Export-I18nBandPreview {
    # Draw the detected bands (and, if given, a grid) onto a downscaled copy of the image, so a human can
    # read coordinates off it instead of guessing. Also accepts externally produced OCR boxes - that is
    # the seam for a real OCR engine later (see tts\docs\I18N.md 1b): same boxes, drawn the same way.
    param(
        [string]$Path,
        [string]$OutPath,
        $Bands,
        [int]$PreviewWidth = 1100,
        [int]$GridStep = 0
    )
    $src = New-Object System.Drawing.Bitmap($Path)
    try {
        $w = [int][Math]::Min($PreviewWidth, $src.Width)
        $sc = $w / [double]$src.Width
        $h = [int][Math]::Round($src.Height * $sc)
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.DrawImage($src, 0, 0, $w, $h)
            if ($GridStep -gt 0) {
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90, 0, 200, 255), 1)
                for ($x = 0; $x -lt $src.Width; $x += $GridStep) { $g.DrawLine($pen, [single]($x * $sc), 0, [single]($x * $sc), $h) }
                for ($y = 0; $y -lt $src.Height; $y += $GridStep) { $g.DrawLine($pen, 0, [single]($y * $sc), $w, [single]($y * $sc)) }
                $pen.Dispose()
            }
            $red = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220, 255, 40, 40), 2)
            $font = New-Object System.Drawing.Font('Consolas', 11)
            $tb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 220, 0))
            $i = 0
            foreach ($b in $Bands) {
                $i++
                $rx = [single]($b.x0 * $sc); $ry = [single]($b.y0 * $sc)
                $rw = [single](($b.x1 - $b.x0) * $sc); $rh = [single](($b.y1 - $b.y0) * $sc)
                $g.DrawRectangle($red, $rx, $ry, $rw, $rh)
                $g.DrawString(('#' + $i + ' y' + $b.y0 + '-' + $b.y1 + ' x' + $b.x0 + '-' + $b.x1), $font, $tb, $rx, [single][Math]::Max(0, $ry - 15))
            }
            $red.Dispose(); $font.Dispose(); $tb.Dispose()
            $g.Dispose()
            $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $bmp.Dispose() }
    } finally { $src.Dispose() }
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
