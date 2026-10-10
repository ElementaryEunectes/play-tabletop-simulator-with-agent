# tr.ps1 - move the table's Turn Tracker BY POSITION, because the tracker's own turn machine is broken.
#
# WHY THIS EXISTS (measured 2026-10-11, see VALIDATION F12)
#   The community "Turn Tracker" token we use advances by calling Player[color].getPlayerHand() - a
#   method this TTS build no longer has. So its End Turn button does nothing for the PLAYER as well
#   (the player confirmed it does not move), and no external path can fix it without editing the mod's
#   script, which was explicitly ruled out.
#
#   What still works is writing a Transform: the piece moves, the colour of the piece does not follow
#   but the turn itself is recorded in the game's STATE.md (this game's single source of truth).
#
#   The two resting places are MEASURED, not guessed: the tracker sat at z=+15 for the agent (Teal) and
#   z=-15 for the player (Brown); x~0.06, y~1.96, rotY=180 is how it rested there. They live in
#   cache\<game>_turn.json next to the zMine/zPlayer that turn_side.ps1 already uses, so there is one
#   place to change if a future table differs.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tr.ps1 -To mine
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tr.ps1 -To player
param(
    [string]$Root = '',
    [string]$Game = '',
    [ValidateSet('mine', 'player')][string]$To = '',
    [int]$DryRun = 0
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
. (Join-Path $Root 'tts\config.ps1')
if ($Game -eq '') { $Game = $DshGame }
if ($Game -eq '') { Write-Host 'ERR no current game (GAME= in local\games\_current.md)'; exit 2 }
if ($To -eq '') { Write-Host 'ERR say -To mine  (hand the turn back to the agent)  or -To player'; exit 2 }

$calibFile = Join-Path $DshCache ($Game + '_turn.json')
if (-not (Test-Path -LiteralPath $calibFile)) { Write-Host "ERR not calibrated: $calibFile"; exit 2 }
$doc = [System.IO.File]::ReadAllText($calibFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

$z = if ($To -eq 'mine') { [double]$doc.zMine } else { [double]$doc.zPlayer }
if ($null -eq $z -or $z -eq 0) { Write-Host 'ERR calibration has no position for that side'; exit 2 }

# x / y / rotY: take them from the calibration when present, else use the measured defaults for the
# table this was calibrated on. Kept here (not in the JSON) so an old calibration file still works.
$point = $null
foreach ($p in $doc.points) { if ([math]::Abs([double]$p.z - $z) -le [double]$doc.tolerance) { $point = $p } }
$x = if ($point) { [double]$point.x } else { 0.06 }
$y = if ($point) { [double]$point.y } else { 1.96 }
if ($y -le 0) { $y = 1.96 }
$rotY = 180

Write-Host ("move tracker {0} -> x={1} y={2} z={3} rotY={4}" -f $doc.tracker, $x, $y, $z, $rotY)
if ($DryRun -eq 1) { Write-Host '(dry run)'; exit 0 }

# Position AND the tracker's saved colour, both together. MEASURED 2026-10-11: writing script_state from
# here DOES stick (the first read-back looked stale only because it was taken too early), and keeping the
# two in step is what makes the hand-off consistent - the piece says whose turn it is and so does the
# mod's own bookkeeping. If stateMine/statePlayer are absent (an old calibration file) only the position
# is written, which still drives our own turn_side.ps1 judgement.
$col = if ($To -eq 'mine') { [string]$doc.stateMine } else { [string]$doc.statePlayer }
$lua = 'local o=getObjectFromGUID("' + $doc.tracker + '") if o==nil then print("tr: NO OBJECT") return end ' +
       'o.setPosition({x=' + $x + ',y=' + $y + ',z=' + $z + '}) ' +
       'o.setRotation({x=0,y=' + $rotY + ',z=0}) '
if ($col -ne '') {
    $lua += 'o.script_state=JSON.encode({"' + $col + '"}) '
    Write-Host ("also set script_state to [""{0}""]" -f $col)
}
$lua += 'print("tr: z=" .. tostring(o.getPosition().z) .. " state=" .. tostring(o.script_state))'
$tmp = Join-Path $DshCache 'tr_move.lua'
[System.IO.File]::WriteAllText($tmp, $lua, (New-Object System.Text.UTF8Encoding($false)))

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tts\tools\exec_script.ps1') -Guid $doc.tracker -LuaFile $tmp
exit $LASTEXITCODE
