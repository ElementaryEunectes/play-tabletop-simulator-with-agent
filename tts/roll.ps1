# roll.ps1 - Dice Throne: roll the hero dice and READ THE FACES, one line per die.
#
# WHY THIS EXISTS
#   "Who goes first" and every attack/defence roll in Dice Throne is "roll 5 dice,
#   read the faces, match a skill pattern". Doing that by hand cost a tool call per
#   die per step. This is the one command a round needs:
#       powershell -NoProfile -ExecutionPolicy Bypass -File tts\roll.ps1
#   => rolls both trays, waits for them to SETTLE, prints the face of each die.
#
# HOW THE FACE IS READ (the whole point of this script)
#   TTS does not expose a die's "shown face" as a method, but a Custom_Dice keeps its
#   own face table: every die in the save carries
#       "RotationValues": [ {"Value":"1","Rotation":{x=-90,y=0,z=0}}, ... 6 entries ]
#   i.e. 6 (rotation -> face-label) pairs, and TTS writes the *matching* label into the
#   die's own Value field when the die settles. So:
#       act getValue    == the authoritative face, straight from TTS.
#   Measured on all 10 dice (6 roll rounds, 2026-10-07): getValue always returned a
#   label whose dominant-axis rotation equalled the settled getRotation, and repeated
#   identical orientations always gave the same label. So getValue IS the face - this
#   script reports it as authoritative and reports the rotation-derived face alongside
#   it as a cross-check, never silently picking one.
#
#   Rotation -> face (verified against the save's RotationValues table, all 10 dice):
#       x=270 -> 1 | (x=0,z=0) -> 2 | z=270 -> 3 | z=90 -> 4 | z=180 -> 5 | x=90 -> 6
#   rotY is free: it is the spin about the vertical axis, so it never changes the face.
#
# GOTCHAS BAKED IN HERE (each one cost a debugging round)
#   * Dice GUIDs are hex strings and MUST stay strings. Sent through
#     ttsx.ps1 -Cmd '...' the quotes around a guid get eaten and 187cc1/656b32/
#     26745c/240f79/033d23 come back as bad JSON or as the NUMBER 910636. So this
#     script does NOT build JSON text: it dot-sources ttslib.ps1 and hands
#     Invoke-Tts a hashtable, so every guid is serialised as a quoted string.
#   * roll() only STARTS a roll. Reading a face immediately returns the PREVIOUS face.
#     So: roll all -> wait -> poll getRotation until it stops changing -> then getValue.
#   * Chinese only ever appears in this file (comments / literals). Never on a
#     command line - that is what corrupted the guid/filter arguments before.
#
# ASCII only outside comments and the two tray labels. Requires the UTF-8 BOM:
# run tts\check_ps1.ps1 after any edit.
#
# USAGE
#   roll.ps1                       # roll both trays, print faces + totals
#   roll.ps1 -First                # same, then print who goes first by total
#   roll.ps1 -Tray moon            # only the Blue (moon elf) tray
#   roll.ps1 -Tray scar -NoRoll    # just read the faces currently showing
#   roll.ps1 -Poll 40              # settle timeout in seconds (default 25)
param(
    [ValidateSet('all', 'moon', 'scar')][string]$Tray = 'all',
    [switch]$NoRoll,
    [switch]$First,
    [int]$Poll = 25,
    [int]$SettleMs = 250,
    [int]$StableHits = 2
)

$ErrorActionPreference = 'Continue'

# ttslib.ps1 is the ONE copy of the TTS TCP transport. Dot-source it: same process,
# one level deep. (Spawning a helper is what the sandbox kills: dsh -> dsh -> script.)
. (Join-Path $PSScriptRoot 'ttslib.ps1')

# --------------------------------------------------------------- the dice table ---
# guid -> tray. Filled from cache\live_index.csv (name contains the hero's die name),
# 2026-10-07. Blue = moon elf, Red = the player's scarlet witch.
# These are per-save: on a NEW game re-filter cache\live_index.csv by name.
$Dice = @(
    @{ guid = [string]'f0738d'; tray = 'moon'; slot = 1 }   # x =  -5, z = 35
    @{ guid = [string]'187cc1'; tray = 'moon'; slot = 2 }   # x =   0, z = 35
    @{ guid = [string]'656b32'; tray = 'moon'; slot = 3 }   # x =   5, z = 35
    @{ guid = [string]'e00b2e'; tray = 'moon'; slot = 4 }   # x =  10, z = 35
    @{ guid = [string]'910636'; tray = 'moon'; slot = 5 }   # x =  15, z = 35
    @{ guid = [string]'205873'; tray = 'scar'; slot = 1 }   # x =  75, z = -35
    @{ guid = [string]'26745c'; tray = 'scar'; slot = 2 }   # x =  80, z = -35
    @{ guid = [string]'aa8300'; tray = 'scar'; slot = 3 }   # x =  85, z = -35
    @{ guid = [string]'240f79'; tray = 'scar'; slot = 4 }   # x =  90, z = -35
    @{ guid = [string]'033d23'; tray = 'scar'; slot = 5 }   # x =  95, z = -35
)

$TrayLabel = @{ moon = 'MoonElf(Blue/me)'; scar = 'ScarletWitch(Red/P1)' }

# --------------------------------------------------------------- tts plumbing -----
# NOTE: the envelope is built from a HASHTABLE, never from a JSON string. See the
# guid-quoting gotcha in the header: a guid must survive as a string end to end.
function Send-Tts {
    param([hashtable]$Message, [int]$Retries = 4)
    $envelope = @{ messageID = 2; customMessage = $Message } | ConvertTo-Json -Depth 10 -Compress
    for ($i = 1; $i -le $Retries; $i++) {
        $r = Invoke-Tts -Envelope $envelope
        if ($null -eq $r.err) { return $r.custom }
        Start-Sleep -Milliseconds 400      # ERR listener busy on 39998: retry
    }
    return $null
}

function Act {
    param([string]$Guid, [string]$Verb)
    return (Send-Tts @{ cmd = 'act'; guid = $Guid; verb = $Verb })
}

# Rotation -> face, from the die's own RotationValues table (see header).
# rotY is deliberately ignored: it is spin about the vertical axis.
function Face-From-Rotation {
    param([string]$Rotation)
    $rx = 0.0; $rz = 0.0
    if ($Rotation -match 'x=([-\d.]+)') { $rx = [double]$Matches[1] }
    if ($Rotation -match 'z=([-\d.]+)') { $rz = [double]$Matches[1] }
    # normalise to 0..360, then to the nearest quarter turn
    $ax = ((($rx % 360) + 360) % 360)
    $az = ((($rz % 360) + 360) % 360)
    $qx = [int][Math]::Round($ax / 90.0) % 4
    $qz = [int][Math]::Round($az / 90.0) % 4
    if ($qx -ne 0) { if ($qx -eq 3) { return 1 } else { return 6 } }   # x=270 -> 1, x=90 -> 6
    switch ($qz) {
        0 { return 2 }   # x=0, z=0
        1 { return 4 }   # z=90
        2 { return 5 }   # z=180
        3 { return 3 }   # z=270
    }
    return 0
}

# --------------------------------------------------------------- roll + settle ----
$target = @($Dice | Where-Object { $Tray -eq 'all' -or $_.tray -eq $Tray })

# The PRE-ROLL rotation of every die, captured before a single roll is sent. It is
# what makes the settle test trustworthy: "unchanged for two polls" is worthless
# right after a roll, because the die may not have started moving yet - the very
# first poll then sees the OLD orientation twice and reads the PREVIOUS face (this
# actually happened: roll.ps1 finished in 4s and reported a stale set).
$before = @{}
foreach ($d in $target) {
    $rot = Act -Guid $d.guid -Verb 'getRotation'
    if ($null -ne $rot) { $before[$d.guid] = [string]$rot.result } else { $before[$d.guid] = '' }
}

if (-not $NoRoll) {
    foreach ($d in $target) {
        $r = Send-Tts @{ cmd = 'act'; guid = $d.guid; verb = 'roll' }
        if ($null -eq $r -or $r.ok -ne $true) {
            Write-Host ("ROLL FAILED " + $d.guid) -ForegroundColor Red
        }
    }
}

# roll() only STARTS the roll. Poll getRotation until the die has MOVED AWAY from its
# pre-roll orientation, then held still for $StableHits consecutive polls; only then is
# getValue the new face. This is the one place where waiting is correct - the dice are
# physics objects and the answer is not ready yet.
$prev = @{}
$hits = @{}
$moved = @{}
$stable = @{}
if ($NoRoll) {
    foreach ($d in $target) { $stable[$d.guid] = $true }     # nothing was thrown: read now
}
$deadline = (Get-Date).AddSeconds($Poll)
$settleStart = Get-Date
while ((Get-Date) -lt $deadline -and $stable.Count -lt $target.Count) {
    $busy = $false
    foreach ($d in $target) {
        if ($stable.ContainsKey($d.guid)) { continue }
        $busy = $true
        $rot = Act -Guid $d.guid -Verb 'getRotation'
        $rs = if ($null -ne $rot) { [string]$rot.result } else { '' }
        if ($rs -eq '') { continue }
        if (-not $moved.ContainsKey($d.guid) -and $rs -ne $before[$d.guid]) { $moved[$d.guid] = $true }
        if ($moved.ContainsKey($d.guid) -and $prev.ContainsKey($d.guid) -and $prev[$d.guid] -eq $rs) {
            $hits[$d.guid] = 1 + [int]$hits[$d.guid]
            if ($hits[$d.guid] -ge $StableHits) { $stable[$d.guid] = $true }
        } else {
            $hits[$d.guid] = 0
        }
        $prev[$d.guid] = $rs
    }
    if ($busy) { Start-Sleep -Milliseconds $SettleMs }
}

$notSettled = @($target | Where-Object { -not $stable.ContainsKey($_.guid) })

# --- transparency ---------------------------------------------------------------
# A die that never confirmed a settle, or one whose getValue disagrees with its own
# rotation, means the reading is NOT trustworthy. Say so loudly instead of printing a
# number that looks fine - a silent stale face is worse than no answer.
if ($notSettled.Count -gt 0) {
    Write-Host ("WARN not settled in {0}s: {1}" -f $Poll, (($notSettled | ForEach-Object { $_.guid }) -join ',')) -ForegroundColor Yellow
}
if (-not $NoRoll) {
    Write-Host ("settle: {0:N1}s  ({1}/{2} dice confirmed still)" -f ((Get-Date) - $settleStart).TotalSeconds, $stable.Count, $target.Count)
}

# --------------------------------------------------------------- read the faces ---
$rows = @()
foreach ($d in $target) {
    $rot = Act -Guid $d.guid -Verb 'getRotation'
    $val = Act -Guid $d.guid -Verb 'getValue'
    $rs = if ($null -ne $rot) { [string]$rot.result } else { '?' }
    $vs = if ($null -ne $val) { [string]$val.result } else { '?' }
    $face = 0
    if ($vs -match '^-?\d+$') { $face = [int]$vs }
    $pred = Face-From-Rotation -Rotation $rs
    $rows += [pscustomobject]@{
        guid = $d.guid; tray = $d.tray; slot = $d.slot
        rot = $rs; face = $face; pred = $pred
    }
}

# --------------------------------------------------------------- one line per die --
foreach ($t in @('moon', 'scar')) {
    $g = @($rows | Where-Object { $_.tray -eq $t })
    if ($g.Count -eq 0) { continue }
    $lbl = $TrayLabel[$t]
    $parts = @()
    $sum = 0
    foreach ($r in ($g | Sort-Object slot)) {
        # TTS's own getValue is authoritative (see header); the rotation-derived face
        # is printed only when the two disagree, so a mismatch can never hide.
        $face = $r.face
        if ($face -le 0) { $face = $r.pred }
        $sum += $face
        $tag = ''
        if ($r.pred -ne $r.face) { $tag = ('!pred' + $r.pred) }
        $parts += ('{0}={1}{2}' -f $r.slot, $face, $tag)
    }
    Write-Host ("{0,-22} {1}   total={2}" -f $lbl, ($parts -join ' '), $sum)
}

if ($First) {
    $m = ($rows | Where-Object { $_.tray -eq 'moon' } | Measure-Object -Property face -Sum).Sum
    $s = ($rows | Where-Object { $_.tray -eq 'scar' } | Measure-Object -Property face -Sum).Sum
    if ($m -gt $s) { $who = 'MoonElf(Blue/me)' }
    elseif ($s -gt $m) { $who = 'ScarletWitch(Red/P1)' }
    else { $who = 'TIE - reroll' }
    Write-Host ("FIRST = {0}  ({1}:{2})" -f $who, $m, $s)
}
