# turn_calib.ps1 - ONE-TIME calibration for "whose turn is it" on a newly taught mod.
#
# WHY THIS EXISTS: seat/zone coordinates differ per mod, so the side that means "my turn" cannot be
# known in advance and must not be inferred (I tried twice: first from screen direction, then by
# pairing a stale coordinate with a later answer - both wrong). This script removes the inference:
# it MEASURES which piece moves when the player ends a turn, RECORDS where it lands, and asks the
# player exactly one question - with the coordinate read in the same run.
#
# WHAT IT WRITES: cache\<game>_turn.json - the single source of truth for every later turn decision:
#   tracker      the guid of the piece the player's End Turn button moves
#   points       the resting position(s) observed, as {x,y,z}
#   side         which point means "my turn" (sideMine) - recorded WITH the evidence that settled it
#   tolerance    how far the piece may sit from a recorded point and still be judged
#
# USAGE
#   # step 1+2: discover the piece (player presses End Turn when asked)
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\turn_calib.ps1 -Discover
#   # step 3: record the answer (no prompt - for the agent to call)
#   powershell ... -File tts\tools\turn_calib.ps1 -Answer mine
#   # check/read the current state any time
#   powershell ... -File tts\tools\turn_calib.ps1 -Show
param(
    [string]$Root = '',
    [string]$Game = '',
    [switch]$Discover,
    [ValidateSet('mine', 'player', '')][string]$Answer = '',
    [switch]$Show,
    [int]$Tolerance = 6
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')
if ($Game -eq '') { $Game = $DshGame }
if ($Game -eq '') { Write-Host 'ERR no current game (GAME= in local\games\_current.md)'; exit 2 }
$CalibFile = Join-Path $DshCache ($Game + '_turn.json')

function Bridge([string]$Do) {
    $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'tts\ds.ps1') -Do $Do -Raw 2>&1 | Out-String
    if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
    try { return ($raw | ConvertFrom-Json).customMessage } catch { return $null }
}
function Snapshot {
    $cm = Bridge 'index:250'
    if ($null -eq $cm) { return $null }
    $items = $cm.items
    if ($items -is [string]) { $items = $items | ConvertFrom-Json }
    return $items
}
function Save([hashtable]$Doc) {
    $json = $Doc | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($CalibFile, $json, (New-Object System.Text.UTF8Encoding($false)))
}
function Load {
    if (-not (Test-Path -LiteralPath $CalibFile)) { return $null }
    return ([System.IO.File]::ReadAllText($CalibFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

# ---------------------------------------------------------------- discover
if ($Discover) {
    $ping = Bridge 'ping'
    if ($null -eq $ping -or $ping.ok -ne $true) { Write-Host 'ERR bridge not reachable (run tts\ds.ps1 -Do ping)'; exit 2 }
    Write-Host ('bridge ok, objects=' + $ping.objects)

    $before = Snapshot
    if ($null -eq $before) { Write-Host 'ERR could not read the table index'; exit 2 }
    Write-Host ('snapshot A: ' + $before.Count + ' objects')

    # ONE prompt, then measure. The wait is deliberate: the player must actually press.
    Write-Host ''
    Write-Host '>>> PRESS "End Turn" ON THE TABLE NOW, then come back and press Enter here.'
    [void](Read-Host '    (waiting)')

    Start-Sleep -Milliseconds 800
    $after = Snapshot
    if ($null -eq $after) { Write-Host 'ERR could not read the table index after the press'; exit 2 }

    $A = @{}
    foreach ($o in $before) { $A[$o.guid] = $o }
    $moved = @()
    foreach ($o in $after) {
        if (-not $A.ContainsKey($o.guid)) { continue }
        $p = $A[$o.guid]
        $dx = [double]$o.x - [double]$p.x
        $dz = [double]$o.z - [double]$p.z
        $d = [math]::Sqrt($dx * $dx + $dz * $dz)
        if ($d -gt 0.05) {
            $moved += [pscustomobject]@{ guid = $o.guid; name = [string]$o.name; d = [math]::Round($d, 2)
                                         x0 = [double]$p.x; z0 = [double]$p.z; x1 = [double]$o.x; z1 = [double]$o.z }
        }
    }
    Write-Host ''
    Write-Host ('moved: ' + $moved.Count + ' object(s)')
    foreach ($m in $moved) { Write-Host ('  guid=' + $m.guid + ' name="' + $m.name + '" moved ' + $m.d + '  (' + $m.x0 + ',' + $m.z0 + ') -> (' + $m.x1 + ',' + $m.z1 + ')') }
    if ($moved.Count -ne 1) {
        Write-Host ''
        Write-Host ('REFUSING TO GUESS: expected exactly ONE piece to move, saw ' + $moved.Count + '.')
        Write-Host 'Re-run -Discover and make sure only the End Turn button is pressed.'
        exit 3
    }
    $t = $moved[0]
    # remember BOTH resting places: the one it left and the one it went to. Later reads accept either.
    $doc = @{
        game      = $Game
        tracker   = $t.guid
        trackerName = $t.name
        points    = @(
            @{ x = $t.x0; y = 0; z = $t.z0 },
            @{ x = $t.x1; y = 0; z = $t.z1 }
        )
        sideMine  = ''
        tolerance = $Tolerance
        evidence  = @()
        updated   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    Save $doc
    Write-Host ''
    Write-Host ('saved ' + $CalibFile)
    Write-Host ('tracker=' + $t.guid + '  resting points: z=' + $t.z0 + ' and z=' + $t.z1)
    Write-Host ''
    Write-Host 'NOW RUN:  turn_calib.ps1 -Answer mine     (if it is YOUR turn right now)'
    Write-Host '     or:  turn_calib.ps1 -Answer player   (if it is the PLAYER''s turn right now)'
    Write-Host 'NOTE: answer for the CURRENT state - the piece has just been moved by that press.'
    exit 0
}

# ---------------------------------------------------------------- answer
if ($Answer -ne '') {
    $doc = Load
    if ($null -eq $doc) { Write-Host 'ERR not calibrated yet - run -Discover first'; exit 2 }
    # sample the piece AT THE SAME MOMENT as the answer, so the pairing cannot go stale
    $cm = Bridge ('index:250')
    $items = $cm.items
    if ($items -is [string]) { $items = $items | ConvertFrom-Json }
    $hit = $items | Where-Object { $_.guid -eq $doc.tracker } | Select-Object -First 1
    if ($null -eq $hit) { Write-Host ('ERR tracker ' + $doc.tracker + ' not on the table right now'); exit 2 }

    $z = [double]$hit.z
    $near = @()
    foreach ($p in $doc.points) { if ([math]::Abs($z - [double]$p.z) -le $doc.tolerance) { $near += [double]$p.z } }
    if ($near.Count -eq 0) {
        Write-Host ('ERR the piece is at z=' + $z + ', which matches neither calibrated point (' +
                    (($doc.points | ForEach-Object { $_.z }) -join ', ') + '). Re-run -Discover.')
        exit 3
    }
    # Record WHICH z means "my turn". Storing the answer as a coordinate - not as an index into the
    # points array - keeps runtime judging to a single comparison and removes any ordering assumption.
    $doc.zMine   = $z
    $doc.zPlayer = $null
    foreach ($p in $doc.points) { if ([math]::Abs([double]$p.z - $z) -gt $doc.tolerance) { $doc.zPlayer = [double]$p.z } }
    $doc.sideMine = $Answer
    $doc.evidence = @($doc.evidence) + @(('player answered "' + $Answer + '" while the piece read z=' + $z +
                                        ' at ' + (Get-Date -Format 'HH:mm:ss')))
    $doc.updated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Save $doc
    Write-Host ('saved: my turn is z=' + $doc.zMine + '  (the other resting place z=' + $doc.zPlayer + ' is the player''s)')
    Write-Host ('evidence: player said "' + $Answer + '" with the piece at z=' + $z + ' at ' + (Get-Date -Format 'HH:mm:ss'))
    Write-Host 'This pairing is now the ONLY basis for later turn decisions.'
    exit 0
}

# ---------------------------------------------------------------- show
$doc = Load
if ($null -eq $doc) { Write-Host ('not calibrated for ' + $Game + ' - run: turn_calib.ps1 -Discover'); exit 2 }
Write-Host ('calibration for ' + $doc.game + '  (updated ' + $doc.updated + ')')
Write-Host ('  tracker   ' + $doc.tracker + '  "' + $doc.trackerName + '"')
Write-Host ('  points    ' + (($doc.points | ForEach-Object { 'z=' + $_.z }) -join '  '))
Write-Host ('  my turn   z=' + $doc.zMine + '     player''s turn   z=' + $doc.zPlayer + '   tolerance ' + $doc.tolerance)
foreach ($e in $doc.evidence) { Write-Host ('  evidence  ' + $e) }
$cm = Bridge 'index:250'
if ($null -ne $cm) {
    $items = $cm.items
    if ($items -is [string]) { $items = $items | ConvertFrom-Json }
    $hit = $items | Where-Object { $_.guid -eq $doc.tracker } | Select-Object -First 1
    if ($null -eq $hit) {
        Write-Host '  now       tracker NOT on the table'
    } else {
        $z = [double]$hit.z
        if ($null -eq $doc.zMine -or $doc.zMine -eq '') {
            Write-Host ('  now       z=' + $z + '  (side not recorded yet - run -Answer mine|player)')
        } elseif ([math]::Abs($z - [double]$doc.zMine) -le $doc.tolerance) {
            Write-Host ('  now       z=' + $z + '  =>  mine')
        } elseif ($null -ne $doc.zPlayer -and [math]::Abs($z - [double]$doc.zPlayer) -le $doc.tolerance) {
            Write-Host ('  now       z=' + $z + '  =>  player')
        } else {
            Write-Host ('  now       z=' + $z + '  =>  UNKNOWN (matches neither resting place) - re-calibrate')
        }
    }
}
exit 0
