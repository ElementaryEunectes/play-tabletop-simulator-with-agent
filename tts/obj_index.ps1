# obj_index.ps1 - full object index of the newest autosave: every object with
# its GUID, internal Name, Nickname, GMNotes, LuaScriptState and position.
#
# WHY: the earlier cache tools (board_images.csv, guids.csv) only kept some kinds
# and dropped the GUID column, so "which GUID is 移动城市 #3?" was unanswerable.
# This writes ONE complete table so lookups are a grep instead of a 25s Lua scan.
#
# Trap encoded here: the autosave is ~2 MB but ConvertFrom-Json on the big
# TS_Save_5.json blew up, so parse with JavaScriptSerializer and a raised
# MaxJsonLength, and walk ObjectStates / ContainedObjects / States / ChildObjects.
param(
    [string]$SavesDir = '',
    [string]$Out = '',
    [string]$File = ''
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($SavesDir -eq '') { $SavesDir = $TtsSavesDir }
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue

if ($File -ne '') { $src = Get-Item $File } else {
    $src = (Get-ChildItem $SavesDir -Filter 'TS_AutoSave*.json' | Sort-Object LastWriteTime -Descending)[0]
}
Write-Host ("save: {0}  {1} KB" -f $src.Name, [int]($src.Length / 1024))
$o = $ser.DeserializeObject([System.IO.File]::ReadAllText($src.FullName, [System.Text.Encoding]::UTF8))

$rows = New-Object System.Collections.ArrayList
function Walk($list, $depth, $parentGuid) {
    if ($depth -gt 6 -or $null -eq $list) { return }
    foreach ($it in $list) {
        if ($null -eq $it) { continue }
        $t = $it['Transform']
        $nm = [string]$it['Name']
        $nick = [string]$it['Nickname']
        $gm = [string]$it['GMNotes']
        $ss = [string]$it['LuaScriptState']
        $urln = ''
        $ci = $it['CustomImage']
        if ($ci) { $urln = [string]$ci['ImageURL'] }
        if ($urln -eq '') {
            $cd = $it['CustomDeck']
            if ($cd) {
                foreach ($p in $cd.PSObject.Properties) { if ($p.Value.FaceURL) { $urln = [string]$p.Value.FaceURL; break } }
            }
        }
        if ($urln -eq '') { $urln = [string]$it['CustomAssetBundle'] }
        $tail = ($urln.TrimEnd('/') -split '/')[-1]
        [void]$rows.Add([pscustomobject]@{
            guid   = [string]$it['GUID']
            name   = $nm
            nick   = $nick
            x      = if ($t) { [math]::Round([double]$t['posX'], 2) } else { 0 }
            y      = if ($t) { [math]::Round([double]$t['posY'], 2) } else { 0 }
            z      = if ($t) { [math]::Round([double]$t['posZ'], 2) } else { 0 }
            sx     = if ($t) { [math]::Round([double]$t['scaleX'], 2) } else { 0 }
            rotY   = if ($t) { [math]::Round([double]$t['rotY'], 1) } else { 0 }
            # rotZ is what says whether a flat card is face UP (~0) or face DOWN (~180).
            # Without it, "did the player flip a card / reveal a cover-placed card?"
            # is unanswerable from the index.
            rotX   = if ($t) { [math]::Round([double]$t['rotX'], 1) } else { 0 }
            rotZ   = if ($t) { [math]::Round([double]$t['rotZ'], 1) } else { 0 }
            gm     = $gm
            ss     = $ss
            url    = $tail
            depth  = $depth
            parent = $parentGuid
        })
        $myGuid = [string]$it['GUID']
        foreach ($k in 'ContainedObjects', 'ChildObjects', 'States') {
            if ($it.ContainsKey($k) -and $it[$k]) { Walk $it[$k] ($depth + 1) $myGuid }
        }
    }
}
Walk $o['ObjectStates'] 0 ''
$rows | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8
Write-Host ("save : {0}   mtime : {1}" -f $src.Name, $src.LastWriteTime.ToString('HH:mm:ss'))
Write-Host ("rows={0}  wrote {1}" -f $rows.Count, $Out)
Write-Host "=== Name histogram ==="
$rows | Group-Object name | Sort-Object Count -Descending | Select-Object -First 25 | ForEach-Object {
    Write-Host ("  {0,-34} {1}" -f $_.Name, $_.Count)
}
