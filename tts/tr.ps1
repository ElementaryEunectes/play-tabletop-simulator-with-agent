# tr.ps1 - move the table's Turn Tracker BY POSITION, because that is the only signal we can write.
#
# WHY THIS EXISTS (measured 2026-10-11, see VALIDATION F12/F13)
#   The tracker's own End Turn button is FINE for the player (F13): a press advances its colour and moves
#   the piece to the successor colour's hand. What does not exist is an EXTERNAL way to press it:
#   Object.call/callx takes TTS down (two runs, never fixed), and the official messageID 3 runs in an
#   empty environment that cannot read the object's private state (F12). So the agent hands the turn
#   over by writing the resting position, and the player's next press carries on from there.
#   (An earlier revision of this comment claimed the button was dead because Player[color].getPlayerHand()
#    no longer exists. MEASURED FALSE - the method exists. The real 2026-10-11 root cause was the empty
#    Name field, fixed by filling in the seat colours plus one player press.)
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
#
# ⭐ THE RULE THE PLAYER NAILED (2026-10-11), their words plus their correction:
#   "you moved the position without changing script_state, so the other side has to press twice"
#   "the press moves the piece to the hand of the NEXT colour after the saved one - so if that next
#    colour is still on this side, the piece goes back to where it already was"
# A press therefore lands the piece on the SUCCESSOR of the saved colour. A hand-over must save the
# colour whose successor sits on the OTHER side: saving Brown sends the next press to Teal's hand (ours),
# saving Teal sends it to Brown's (the player's). That is what -State carries, and it is what keeps a
# hand-over down to ONE press.
param(
    [string]$Root = '',
    [string]$Game = '',
    [ValidateSet('mine', 'player')][string]$To = '',
    # 'auto' rather than '' on purpose: this repo's param-backfill gate requires every '' default to be
    # backfilled or tested after config.ps1, and 'auto' states the meaning anyway (follow -To).
    [ValidateSet('mine', 'player', 'auto')][string]$State = 'auto',
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

# POSITION AND SAVED COLOUR, BOTH - this is what keeps a hand-over to ONE press (see the header).
#
# What each write does (measured 2026-10-11):
#   * setPosition / setRotation -> effective; this is what turn_side.ps1 reads.
#   * o.script_state = ...      -> updates the SAVED colour; it does NOT change the running `currentColor`
#                                  inside the object's environment. The button press reads the running
#                                  variable, but it MOVES the piece to the hand of the saved colour's
#                                  successor - which is exactly why the saved colour has to match the side
#                                  we are handing to, or the next press lands the piece where it already is.
$col = if ($State -eq 'mine') { [string]$doc.stateMine }
       elseif ($State -eq 'player') { [string]$doc.statePlayer }
       else { if ($To -eq 'mine') { [string]$doc.stateMine } else { [string]$doc.statePlayer } }
$point = $null
foreach ($p in $doc.points) { if ([math]::Abs([double]$p.z - $z) -le [double]$doc.tolerance) { $point = $p } }
$x = if ($point) { [double]$point.x } else { 0.06 }
$y = if ($point) { [double]$point.y } else { 1.96 }
if ($y -le 0) { $y = 1.96 }
$rotY = 180

Write-Host ("move tracker {0} -> x={1} y={2} z={3} rotY={4} saved-colour={5}" -f $doc.tracker, $x, $y, $z, $rotY, $col)
Write-Host 'NOTE: turn_side.ps1 reads the POSITION; the saved colour is what makes the player''s next press land on the other side (one press, not two).'
if ($DryRun -eq 1) { Write-Host '(dry run)'; exit 0 }

# The write itself. Do not judge it by one quick read-back: an early sample can look stale simply because
# it was taken before the write landed (that is how I wrongly concluded "state writes do not stick").
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
