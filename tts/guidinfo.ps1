# guidinfo.ps1 - extract identity fields for specific GUIDS straight out of the save text.
#
# WHY THIS EXISTS: FaceURL alone does NOT identify a card. When a deck's face image is a
# SHEET (NumWidth x NumHeight grid holding several different cards), every card in the deck
# shares the same FaceURL and differs only by `CardID`. CardID = deckId*100 + cellIndex,
# cellIndex running left-to-right, top-to-bottom over the grid.
#
# Regex extraction, NOT JavaScriptSerializer: the serializer throws ArgumentException
# (recursion / MaxJsonLength) on these saves, and the raw text is enough.
#
# USAGE
#   powershell -File guidinfo.ps1 -Guid 2b0a81,412b36
#   powershell -File guidinfo.ps1 -Guid 2b0a81 -Save C:\...\TS_Save_5.json
# NOTE: param() must stay the FIRST statement in this file; the config dot-source comes after.
param(
    [Parameter(Mandatory = $true)][string[]]$Guid,
    [string]$Save = '',
    [int]$Window = 1600
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($Save -eq '') { $Save = Join-Path $TtsSavesDir 'TS_AutoSave.json' }
$ErrorActionPreference = 'Stop'

# `powershell -File x.ps1 -Guid a,b,c` hands the whole "a,b,c" over as ONE string, so split it.
$Guid = @($Guid | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' })
if (-not (Test-Path -LiteralPath $Save)) { Write-Host ("ERR no save at {0}" -f $Save); exit 1 }
$fi = Get-Item -LiteralPath $Save
Write-Host ("save : {0}  mtime : {1}" -f $fi.Name, $fi.LastWriteTime.ToString('MM-dd HH:mm:ss'))

$txt = Get-Content -Raw -LiteralPath $Save
foreach ($g in $Guid) {
    $m = [regex]::Match($txt, '"GUID":\s*"' + [regex]::Escape($g) + '"')
    if (-not $m.Success) { Write-Host ("{0}  NOT IN SAVE" -f $g); continue }
    $start = $m.Index
    $len = [math]::Min($Window, ($txt.Length - $start))
    $chunk = $txt.Substring($start, $len)

    $name = [regex]::Match($chunk, '"Name":\s*"([^"]*)"').Groups[1].Value
    $cid  = [regex]::Match($chunk, '"CardID":\s*(\d+)').Groups[1].Value
    $nw   = [regex]::Match($chunk, '"NumWidth":\s*(\d+)').Groups[1].Value
    $nh   = [regex]::Match($chunk, '"NumHeight":\s*(\d+)').Groups[1].Value
    $face = [regex]::Match($chunk, '"FaceURL":\s*"([^"]*)"').Groups[1].Value
    $back = [regex]::Match($chunk, '"BackURL":\s*"([^"]*)"').Groups[1].Value
    $px   = [regex]::Match($chunk, '"posX":\s*([-\d.eE+]+)').Groups[1].Value
    $py   = [regex]::Match($chunk, '"posY":\s*([-\d.eE+]+)').Groups[1].Value
    $pz   = [regex]::Match($chunk, '"posZ":\s*([-\d.eE+]+)').Groups[1].Value

    $faceTail = $face
    if ($faceTail.Length -gt 40) { $faceTail = $faceTail.Substring($faceTail.Length - 40) }

    Write-Host ("{0}  name={1}" -f $g, $name)
    if ($cid) {
        $cidNum = [int]$cid
        $deck = [math]::Floor($cidNum / 100)
        $cell = $cidNum - ($deck * 100)
        Write-Host ("    CardID={0}  (deck {1} x cell {2})   sheet grid {3}x{4}" -f $cid, $deck, $cell, $nw, $nh)
    }
    Write-Host ("    faceTail={0}" -f $faceTail)
    Write-Host ("    pos=({0},{1},{2})" -f $px, $py, $pz)
}
