param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Out,
    [double]$Scale = 4.0,
    [int]$X = 0, [int]$Y = 0, [int]$W = 0, [int]$H = 0,
    [switch]$NoUpscale
)
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile($Source)
$rx = $X; $ry = $Y; $rw = $W; $rh = $H
if ($rw -le 0) { $rw = $img.Width }
if ($rh -le 0) { $rh = $img.Height }
if ($rx + $rw -gt $img.Width)  { $rw = $img.Width - $rx }
if ($ry + $rh -gt $img.Height) { $rh = $img.Height - $ry }
if ($NoUpscale) { $Scale = 1.0 }
$ow = [int]($rw * $Scale); $oh = [int]($rh * $Scale)
$bmp = New-Object System.Drawing.Bitmap($ow, $oh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode  = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.SmoothingMode    = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.DrawImage($img, (New-Object System.Drawing.Rectangle(0,0,$ow,$oh)), (New-Object System.Drawing.Rectangle($rx,$ry,$rw,$rh)), [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose(); $img.Dispose()
Write-Host ("{0}  src {1}x{2} crop({3},{4},{5},{6}) x{7} -> {8}x{9}  {10}" -f (Split-Path $Source -Leaf), $img.Width, $img.Height, $rx, $ry, $rw, $rh, $Scale, $ow, $oh, $Out)
