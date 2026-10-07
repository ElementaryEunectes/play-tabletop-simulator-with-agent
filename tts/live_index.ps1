# live_index.ps1 - a LIVE snapshot of the whole table (positions + rotations), in the
# same CSV shape as obj_index.ps1, so diff_index.ps1 can diff it.
#
# WHY NOT JUST USE obj_index.ps1
#   obj_index.ps1 parses the AUTOSAVE, which TTS only writes every ~5 minutes. Reading it
#   right after the player acts shows the OLD table - verified the hard way: a card was
#   flipped, obj_index was re-run 3 s later, and the diff reported "nothing changed".
#   For "what did the player just do?" you need the running game, not the file.
#
# HOW
#   ds.ps1 -Do 'all:1200' -Raw asks the game for every object with position + rotation.
#   Since the flat-reply fix (v10-flatreply) that used to be impossible - `all` returns a
#   LIST, and a list-returning handler used to die silently. Now it arrives as a (SON
#   STRING in the `items` field, which is parsed here.
#
# LIMITS vs obj_index.ps1
#   no scale, no GMNotes, no LuaScriptState, no parent, no image url.
#   => it detects MOVES and FLIPS (what player actions look like) but NOT counter changes
#      or container changes. Read counters separately with act:<guid>:getGMNotes.
param(
    [string]$Out = '',
    [int]$Limit = 1200,
    [string]$DsPs1 = ''
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($DsPs1 -eq '') { $DsPs1 = (Join-Path $DshTts 'ds.ps1') }
if ($Out -eq '') { $Out = (Join-Path $DshCache 'live_index.csv') }
$ErrorActionPreference = 'Stop'
# In-process call to ds.ps1 (was `& powershell -NoProfile -File ds.ps1`, which cost
# ~600 ms of PowerShell process start on EVERY snapshot). Two things make it safe:
#   * ds.ps1 now uses `return` instead of a top-level `exit`, so it cannot kill us;
#   * `6>&1` -- NOT `|` -- is required to capture its output, because ds.ps1 prints
#     with Write-Host, which goes to the INFORMATION stream and bypasses the pipeline.
$raw = & $DsPs1 -Do ("all:{0}" -f $Limit) -Raw 6>&1
if (-not $raw) { Write-Host "ERR no reply from TTS"; exit 1 }
$line = ($raw -join "`n")
# -Raw prints the envelope verbatim and it arrives PRETTY-PRINTED (multi-line). (oin every
# line before parsing: keeping only the line that contains "customMessage" leaves the
# fragment '  "customMessage": {' and ConvertFrom-Json fails on it.
$env = $null
try { $env = $line | ConvertFrom-Json } catch { Write-Host ("PARSE-FAIL: {0}" -f $line.Substring(0, [math]::Min(200, $line.Length))); exit 1 }
$resp = $env.customMessage
if ($resp.ok -ne $true) { Write-Host ("FAIL {0}" -f $resp.err); exit 1 }
$items = $resp.items | ConvertFrom-Json
$rows = foreach ($it in $items) {
    $rz = 0; $ry = 0
    if ($it.r) { $p = "$($it.r)" -split ','; if ($p.Count -ge 3) { $ry = [double]$p[1]; $rz = [double]$p[2] } }
    [pscustomobject]@{
        guid = "$($it.g)"; name = "$($it.n)"; nick = "$($it.k)"
        x = [double]$it.x; y = [double]$it.y; z = [double]$it.z
        sx = ''; rotY = $ry; gm = ''; ss = ''; url = ''; depth = ''; parent = ''
        rotX = 0; rotZ = $rz
    }
}
$rows | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8
Write-Host ("live index: {0} objects (game reports total={1}) -> {2}" -f @($rows).Count, $resp.total, $Out)