# bags_dump.ps1 - list every container in the save with its contents, including the
# nested bags that hold the game's supply piles.
#
# WHY: the resource-point indicators (资源点指示物) are spawned from inside an
# Infinite_Bag, and TTS does not create top-level objects for a bag's contents until
# they are taken out. So "find:资源点指示物" and the flat object index both miss
# them, and their GUIDs - needed to place one on a resource point - were unknown.
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
$lines = New-Object System.Collections.ArrayList
[void]$lines.Add("save: " + $src.Name)
$o = $ser.DeserializeObject([System.IO.File]::ReadAllText($src.FullName, [System.Text.Encoding]::UTF8))

function Tail([string]$u) { if ($u -eq '') { return '' }; $t = ($u.TrimEnd('/') -split '/')[-1]; return $t.Substring(0, [Math]::Min(16, $t.Length)) }

function Walk($list, $depth, $path) {
    if ($depth -gt 6 -or $null -eq $list) { return }
    foreach ($it in $list) {
        if ($null -eq $it) { continue }
        $nm = [string]$it['Name']
        $nick = [string]$it['Nickname']
        $g = [string]$it['GUID']
        $t = $it['Transform']
        $co = $it['ContainedObjects']
        $n = 0
        if ($co) { $n = @($co).Count }
        $img = ''
        $ci = $it['CustomImage']; if ($ci) { $img = Tail ([string]$ci['ImageURL']) }
        if ($img -eq '') { $ab = [string]$it['CustomAssetBundle']; $img = Tail $ab }
        $mark = ''
        if ($n -gt 0) { $mark = "  <CONTAINS $n>" }
        $px = ''; $pz = ''
        if ($t) { $px = [math]::Round([double]$t['posX'], 1); $pz = [math]::Round([double]$t['posZ'], 1) }
        $indent = '  ' * $depth
        $line = "{0}{1,-26} {2} nick=[{3}] x={4} z={5} img={6}{7}" -f $indent, $nm, $g, $nick, $px, $pz, $img, $mark
        [void]$lines.Add($line)
        # print child GUIDs of small containers so each contained object is named
        if ($co -and $n -gt 0 -and $n -le 40) {
            foreach ($c in $co) {
                if ($null -eq $c) { continue }
                $cn = [string]$c['Name']; $cg = [string]$c['GUID']; $cnick = [string]$c['Nickname']
                $cgm = [string]$c['GMNotes']
                $ccs = [string]$c['LuaScriptState']
                $ct = $c['CustomImage']
                $cimg = ''; if ($ct) { $cimg = Tail ([string]$ct['ImageURL']) }
                if ($cimg -eq '') { $cimg = Tail ([string]$c['CustomAssetBundle']) }
                [void]$lines.Add(("{0}    - {1,-20} {2} nick=[{3}] img={4} gm=[{5}] ss=[{6}]" -f $indent, $cn, $cg, $cnick, $cimg, $cgm, $ccs))
            }
        }
        foreach ($k in 'ContainedObjects', 'ChildObjects', 'States') {
            if ($it.ContainsKey($k) -and $it[$k]) { Walk $it[$k] ($depth + 1) $path }
        }
    }
}
Walk $o['ObjectStates'] 0 ''
$lines | Set-Content -LiteralPath $Out -Encoding UTF8
Write-Host ("wrote {0}  lines={1}" -f $Out, $lines.Count)
