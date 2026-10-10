# dump_lua.ps1 - pull the LuaScript of save objects out of a SAVE FILE (offline; no TTS, no bridge).
#
# WHY
#   Some of the pieces we work with are workshop items whose script lives ONLY inside the save (the
#   community Turn Tracker is one). Editing such a script is editing the save: no repository, no
#   history, nothing to diff against - so the step before touching it is to pull a copy out.
#   It also answers "what does this mod's object actually run?" without driving the running game.
#
#   Supersedes ~\.dsh\archive\tts-legacy\dump_scripts.ps1, which did the same walk with two
#   hard-coded machine paths and always wrote every script.
#
# WHAT IT DOES
#   * walks the save: ObjectStates / ContainedObjects / ChildObjects / States, depth <= 8
#   * default: write EVERY LuaScript >= -MinChars to <OutDir> files named <n>_<guid>.lua, one line each
#   * -Guid <g>: that ONE object only, to -OutFile (default <OutDir>\<guid>.lua) - the backup case
#   * -List: report what it found and write nothing
#   * -Save <file>: use that save instead of the newest TS_AutoSave*.json
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\dump_lua.ps1 -Guid <guid> -OutFile local\games\<game>\tracker.lua
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\dump_lua.ps1 -List
#
# ASCII only.
param(
    [string]$Root = '',
    [string]$SavesDir = '',
    [string]$Save = '',
    [string]$Guid = '',
    [string]$OutDir = '',
    [string]$OutFile = '',
    [int]$MinChars = 50,
    [switch]$List
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')
if ($SavesDir -eq '') { $SavesDir = $TtsSavesDir }
if ($OutDir -eq '') { $OutDir = (Join-Path $DshCache 'scripts') }
if ($Save -eq '') {
    $newest = Get-ChildItem $SavesDir -Filter 'TS_AutoSave*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $newest) { Write-Host ("ERR no TS_AutoSave*.json under {0}" -f $SavesDir); exit 2 }
    $Save = $newest.FullName
}
if (-not (Test-Path -LiteralPath $Save)) { Write-Host ("ERR no such save: {0}" -f $Save); exit 2 }

Add-Type -AssemblyName System.Web.Extensions
$ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$ser.MaxJsonLength = [int]::MaxValue
# The autosave is ~2 MB and a mod's Global Lua is ~116 KB: ConvertFrom-Json blows up on these, and that
# is why every reader in this repo uses JavaScriptSerializer with a raised MaxJsonLength.
$doc = $ser.DeserializeObject([System.IO.File]::ReadAllText($Save, [System.Text.Encoding]::UTF8))
Write-Host ("save: {0}" -f (Split-Path $Save -Leaf))

$rows = New-Object System.Collections.ArrayList
function Walk($list, $depth) {
    if ($depth -gt 8 -or $null -eq $list) { return }
    foreach ($it in $list) {
        if ($null -eq $it) { continue }
        $code = [string]$it['LuaScript']
        if ($code.Length -ge $MinChars) {
            [void]$rows.Add([pscustomobject]@{
                guid  = [string]$it['GUID']
                name  = [string]$it['Name']
                nick  = [string]$it['Nickname']
                state = [string]$it['LuaScriptState']
                code  = $code
            })
        }
        # Containers are where the interesting pieces hide (the tracker sits inside no bag today, but a
        # deck's cards and a bag's tokens both carry their own LuaScript).
        foreach ($k in 'ObjectStates', 'ContainedObjects', 'ChildObjects', 'States') {
            $child = $it[$k]
            if ($null -ne $child) { Walk $child ($depth + 1) }
        }
    }
}
Walk $doc.ObjectStates 1

function Write-One([string]$path, [string]$text) {
    $dir = Split-Path -Parent $path
    if ($dir -ne '' -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

if ($Guid -ne '') {
    $hit = @($rows | Where-Object { $_.guid -eq $Guid })
    if ($hit.Count -eq 0) {
        Write-Host ("ERR no object with guid {0} carrying a LuaScript of >= {1} chars" -f $Guid, $MinChars)
        exit 2
    }
    $target = if ($OutFile -ne '') { $OutFile } else { Join-Path $OutDir ($Guid + '.lua') }
    Write-One $target $hit[0].code
    # Line count the way an editor sees it: a trailing newline does not make an extra line.
    $lines = $hit[0].code.TrimEnd("`r", "`n").Split("`n").Count
    Write-Host ("wrote {0}  bytes={1} lines={2}  guid={3} name={4} nick=[{5}]" -f `
        $target, $hit[0].code.Length, $lines, $hit[0].guid, $hit[0].name, $hit[0].nick)
    exit 0
}

$i = 0
foreach ($r in $rows) {
    $i++
    $line = ("[{0}] guid={1} name={2} nick=[{3}] chars={4} state={5}" -f $i, $r.guid, $r.name, $r.nick, $r.code.Length, $r.state)
    if ($List) { Write-Host $line; continue }
    Write-One (Join-Path $OutDir ("{0}_{1}.lua" -f $i, $r.guid)) $r.code
    Write-Host $line
}
Write-Host ("objects with a LuaScript >= {0} chars: {1}" -f $MinChars, $rows.Count)
if (-not $List) { Write-Host ("out: {0}" -f $OutDir) }
exit 0
