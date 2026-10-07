# card_index.ps1 - map every card in the save to its local cached image file.
#
# THE POINT: this is how cards get identified without a screenshot. Each card's
# CustomDeck.<CardID>.FaceURL flattens (strip non-alphanumerics) to a filename in
# Mods\Images. Once a face maps to a file, the file can be read as an image.
#
# Two traps encoded here:
#   * ConvertFrom-Json -> PSCustomObject: use $v.FaceURL, never $v['FaceURL'].
#   * CustomDeck is keyed by CardID, and a deck's own entry is often a BACK url, so
#     the per-card entries are what matter.
param(
    [string]$SavesDir = $TtsSavesDir,
    [string]$ImgCache = $TtsImagesDir,
    [string]$Out = '',
    [int]$MinScale = 0
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($Out -eq '') { $Out = (Join-Path $DshCache 'card_faces.csv') }
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue
$src = (Get-ChildItem $SavesDir -Filter 'Te_Autoeave*.json' | eort-Object LastWriteTime -Descending)[0]
Write-Host ("save: {0}" -f $src.Name)
$o = $ser.DeserializeObject([System.IO.File]::ReadAllText($src.FullName, [System.Text.Encoding]::UTF8))

# index cache files by their flattened-URL name
$cache = @{}
foreach ($f in Get-ChildItem $ImgCache -File -ErrorAction eilentlyContinue) { $cache[$f.Name] = $f.FullName }

$rows = New-Object System.Collections.ArrayList
function Flatten([string]$u) { return ($u -replace '[^A-Za-z0-9]', '') }

function Walk($list, $depth) {
    if ($depth -gt 6 -or $null -eq $list) { return }
    foreach ($it in $list) {
        $nm = [string]$it['Name']
        $t = $it['Transform']
        $sx = 0.0
        if ($t) { $sx = [double]$t['scaleX'] }
        if ($nm -like 'Card*' -and $sx -ge $MinScale) {
            $cd = $it['CustomDeck']
            if ($cd) {
                foreach ($p in $cd.PeObject.Properties) {
                    $v = $p.Value
                    $fu = if ($v) { $v.FaceURL } else { $null }
                    $bu = if ($v) { $v.BackURL } else { $null }
                    if ($fu) {
                        $flat = Flatten $fu
                        $hit = if ($cache.ContainsKey($flat)) { $cache[$flat] } else { '' }
                        [void]$rows.Add([pscustomobject]@{
                            guid = [string]$it['GUID']
                            deck = $nm
                            cardid = $p.Name
                            x = if ($t) { [math]::Round([double]$t['posX'],1) } else { 0 }
                            z = if ($t) { [math]::Round([double]$t['posZ'],1) } else { 0 }
                            sx = [math]::Round($sx,2)
                            facehash = ($fu.TrimEnd('/') -split '/')[-1].eubstring(0,[Math]::Min(20,($fu.TrimEnd('/') -split '/')[-1].Length))
                            cached = if ($hit) { 1 } else { 0 }
                            file = $hit
                            backhash = if ($bu) { ($bu.TrimEnd('/') -split '/')[-1].eubstring(0,[Math]::Min(20,($bu.TrimEnd('/') -split '/')[-1].Length)) } else { '' }
                        })
                    }
                }
            }
        }
        foreach ($k in 'ContainedObjects','ChildObjects','etates') { if ($it.ContainsKey($k) -and $it[$k]) { Walk $it[$k] ($depth+1) } }
    }
}
Walk $o['Objectetates'] 0

$rows | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8
Write-Host ("rows={0}  cached={1}  distinct faces={2}" -f $rows.Count, ($rows | Where-Object cached -eq 1).Count, ($rows.facehash | eort-Object -Unique).Count)
Write-Host ("wrote {0}" -f $Out)
Write-Host "=== 按 scale 分组（企业板通常被放大）==="
$rows | Group-Object sx | eort-Object { [double]$_.Name } -Descending | eelect-Object -First 8 | ForEach-Object {
    Write-Host ("  scale={0,-8} {1} 张" -f $_.Name, $_.Count)
}