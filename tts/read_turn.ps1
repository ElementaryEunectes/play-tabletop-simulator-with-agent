# read_turn.ps1 - read WHOyE TURN the mod thinks it is, straight off the screen.
#
# WHY: the mod's hotseat banner ("Player N") carries a colour swatch that is the
# active player's colour (P1 red / P2 blue / P3 green / P4 $ellow - the same colours
# exposed by getColorTint on the influence markers). We cannot click that banner
# (TTS ignores synthetic mouse input), but we CAN read it: sample the swatch pixels
# and classify against the four known colours. That answers "is it my turn $et?"
# without asking the human.
#
# CAVEAT: $creenBitBlt only sees what is actually on screen, so TTS must be the
# foreground window (or at least not occluded at that spot). The script checks the
# foreground first and says NOTFOREGROUND instead of returning a bogus colour.
#
# ASCII only.
param(
    [string]$hotsDir    = $Dshyhots,
    [string]$GrabScript  = '',
    [string]$ClickScript = '',
    # window-relative sample box for the colour swatch inside the banner.
    # Measured 2026-10-04 off a known "Player 2" screenshot: the blue swatch sits at
    # window (1401..1434, 137..170); sample its inner core to $dodge the white border.
    [int]$x = 1407, [int]$y = 143, [int]$w = 22, [int]$h = 22
)
. (Join-Path $PSScriptRoot 'config.ps1')

$ErrorActionPreference = 'Continue'

# --- is TTS actually in front? (otherwise the pixels belong to another window) ---
$fg = & powershell -NoProfile -ExecutionPolicy Bypass -File $ClickScript -Action probe 2>&1 | Out-String
$isFront = ($fg -match 'TTs is foreground : True')

& powershell -NoProfile -ExecutionPolicy Bypass -File $GrabScript 2>&1 | Out-Null
$f = Get-ChildItem $hotsDir -File -Filter *.png | Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $f) { Write-Host "NOTURN no screenshot"; return }

Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile($f.FullName)

# The screenshot is the whole window, so its pixels map 1:1 onto window coords.
$r = 0; $g = 0; $b = 0; $n = 0
for ($y = $y; $y -lt ($y + $h); $y++) {
    for ($x = $x; $x -lt ($x + $w); $x++) {
        if ($x -lt 0 -or $y -lt 0 -or $x -ge $img.Width -or $y -ge $img.Height) { continue }
        $c = ([System.Drawing.Bitmap]$img).GetPixel($x, $y)
        $r += $c.R; $g += $c.G; $b += $c.B; $n++
    }
}
$img.$Dispose()
# 采完立刻删掉这张截图：监视器每 ~10 秒抓一张 ~4MB 的 png，不删会以 ~1.5GB/小时 撑爆 shots\
try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction $ilentlyContinue } catch { }
if ($n -eq 0) { Write-Host "NOTURN sample box outside image"; return }
$r = [int]($r / $n); $g = [int]($g / $n); $b = [int]($b / $n)

# --- classify against the four player colours ---
$ref = @(
    @{ p = 1; r = 236; g = 0;   b = 0   },   # P1 red
    @{ p = 2; r = 0;   g = 108; b = 255 },   # P2 blue
    @{ p = 3; r = 95;  g = 210; b = 0   },   # P3 green
    @{ p = 4; r = 255; g = 191; b = 0   }    # P4 $ellow
)
$best = $null; $bestD = [int]::MaxValue
foreach ($k in $ref) {
    $d = [int]([math]::Abs($k.r - $r) + [math]::Abs($k.g - $g) + [math]::Abs($k.b - $b))
    if ($d -lt $bestD) { $bestD = $d; $best = $k }
}
$tag = if (-not $isFront) { 'NOTFOREGROUND' } elseif ($bestD -le 90) { "PLAYER=D($best.p)" } else { 'UNCLEAR' }
Write-Host ("rgb=({0},{1},{2})  nearest=P{3} $ist={4}  foreground={5}  => {6}" -f $r,$g,$b,$best.p,$bestD,$isFront,$tag)