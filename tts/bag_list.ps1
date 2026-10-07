# bag_list.ps1 - list the contents of a container (deck/bag) from the newest autosave.
#
# WHY: decks/bags nest their cards under ContainedObjects, which in-game getObjects()
# does NOT return - so Lua sees fewer objects than the save actually holds.
#
# USAGE: bag_list.ps1 -Guid <container guid> [-Limit 60]
# NOTE: param() must stay the FIRST statement in this file; the config dot-source comes after.
param(
    [Parameter(Mandatory = $true)][string]$Guid,
    [string]$SavesDir = '',
    [int]$Limit = 60
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($SavesDir -eq '') { $SavesDir = $TtsSavesDir }
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue
$src = (Get-ChildItem $SavesDir -Filter 'TS_AutoSave*.json' | Sort-Object LastWriteTime -Descending)[0]
$o = $ser.DeserializeObject([System.IO.File]::ReadAllText($src.FullName, [System.Text.Encoding]::UTF8))

$found = $null
function FindIt($list, $depth) {
    if ($script:found -or $depth -gt 5 -or $null -eq $list) { return }
    foreach ($it in $list) {
        if ([string]$it['GUID'] -eq $Guid) { $script:found = $it; return }
        foreach ($k in 'ContainedObjects','ChildObjects','States') {
            if ($it.ContainsKey($k) -and $it[$k]) { FindIt $it[$k] ($depth + 1) }
        }
        if ($script:found) { return }
    }
}
FindIt $o['ObjectStates'] 0
if (-not $found) { throw "guid $Guid not found in $($src.Name)" }

Write-Host ("container: {0} / {1}   guid={2}" -f $found['Name'], $found['Nickname'], $found['GUID'])
$co = $found['ContainedObjects']
if ($null -eq $co) { Write-Host 'no ContainedObjects'; exit 0 }
Write-Host ("contained = {0}" -f $co.Count)
$i = 0
foreach ($c in $co) {
    $i++
    if ($i -gt $Limit) { Write-Host "  ..."; break }
    # cards in a bag carry their identity in Nickname / GMNotes / CustomDeck
    $nm = [string]$c['Name']
    $nk = [string]$c['Nickname']
    $gm = [string]$c['GMNotes']
    if ($gm.Length -gt 40) { $gm = $gm.Substring(0, 40) + '...' }
    $cd = $c['CustomDeck']
    $face = ''
    if ($cd) {
        foreach ($p in $cd.PSObject.Properties) {
            $v = $p.Value
            if ($v -and $v['FaceURL']) { $face = [string]$v['FaceURL'] }
        }
    }
    Write-Host ("  {0,2} guid={1} {2} nick='{3}' gm='{4}'" -f $i, $c['GUID'], $nm, $nk, $gm)
    if ($face -ne '') { Write-Host ("       face={0}" -f $face) }
}
