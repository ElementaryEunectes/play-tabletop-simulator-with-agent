# tts\lib\play.dice.ps1 - split out of play.ps1 (2026-10-08) so it can be READ on its own.
# play.ps1 dot-sources this: SAME process, no extra PowerShell start-up (0.35 s each). Never spawn it.

function Seat-Obj([string]$s) { return $Rules.dice.$s }

# face (1..6) -> symbol label. Face 6 of the moon elf shows TWO symbols; see the
# matcher below, where one such die satisfies one of them, never both.
function Symbol-Of([string]$s, [int]$face) {
    $d = As-Dict (Seat-Obj $s).faces
    $k = [string]$face
    if ($d.ContainsKey($k)) { return [string]$d[$k] }
    return '?'
}

function Face-From-Rotation([string]$Rotation) {
    $rx = 0.0; $rz = 0.0
    if ($Rotation -match 'x=([-\d.]+)') { $rx = [double]$Matches[1] }
    if ($Rotation -match 'z=([-\d.]+)') { $rz = [double]$Matches[1] }
    $ax = ((($rx % 360) + 360) % 360)
    $az = ((($rz % 360) + 360) % 360)
    $qx = [int][Math]::Round($ax / 90.0) % 4
    $qz = [int][Math]::Round($az / 90.0) % 4
    if ($qx -ne 0) { if ($qx -eq 3) { return 1 } else { return 6 } }
    switch ($qz) { 0 { return 2 } 1 { return 4 } 2 { return 5 } 3 { return 3 } }
    return 0
}

function Get-Rotation([string]$g) {
    $c = Bridge @{ cmd = 'act'; guid = $g; verb = 'getRotation' }
    if ($null -eq $c.result) { return '' }
    return [string]$c.result
}

# Face read: getValue is authoritative (roll.ps1 proved this over 6 rounds of
# cross-checks); the rotation-derived face is only used to WARN, never to overwrite.
function Get-Face([string]$g, [string]$seat) {
    $c = Bridge @{ cmd = 'act'; guid = $g; verb = 'getValue' }
    $s = ''
    if ($null -ne $c.result) { $s = [string]$c.result }
    $face = 0
    if ($s -match '^-?\d+$') { $face = [int]$s }
    $rot = Get-Rotation $g
    $pred = Face-From-Rotation $rot
    if ($face -le 0 -or $face -gt 6) {
        if ($pred -ge 1 -and $pred -le 6) { Write-Host ("WARN getValue unusable on $g, used rotation face") }
        else { Fail 'BAD DATA' ("die $g returned no face (getValue: " + $s + ")") }
        $face = $pred
    } elseif ($pred -ne $face) {
        Write-Host ("WARN die $g face/rotation disagree (value=$face rot=$pred)")
    }
    return $face
}

# Set-StrictMode 2.0 makes reading a MISSING property a hard error, and ConvertFrom-Json
# silently drops JSON nulls. So every optional field in the data file must be asked for
# with Has, never with a bare property read.
function Roll-Dice([string]$seat, [int[]]$Keep, [bool]$NoRoll) {
    $g = @($Rules.dice.$seat.guids)   # .<name> form: PS 5.1 cannot index a PSCustomObject by [$var]
    if ($null -eq $g -or $g.Count -ne 5) { Fail 'LOOKUP' ("no dice table for seat " + $seat) }
    if ($NoRoll) {
        # -NoRoll must not touch the table AT ALL (not even the lock bits): a live turn
        # may be in progress and reading the current faces is the whole point.
        $faces = @{}
        $status = @{}
        for ($i = 0; $i -lt 5; $i++) {
            $faces[$i + 1] = Get-Face $g[$i] $seat
            $status[$g[$i]] = 'read'
        }
        return @{ faces = $faces; status = $status; guids = $g }
    }
    $keepSet = @{}
    foreach ($k in @($Keep)) {
        if ($k -lt 1 -or $k -gt 5) { Fail 'BAD DATA' ("-Lock slot out of range: " + $k + " (1..5)") }
        $keepSet[$k] = $true
    }
    # Locked slots are kept: set the lock BEFORE rolling, and roll only the rest.
    for ($i = 0; $i -lt 5; $i++) {
        $slot = $i + 1
        Set-Lock $g[$i] ($keepSet.ContainsKey($slot))
    }
    $target = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt 5; $i++) {
        if (-not $keepSet.ContainsKey($i + 1)) { [void]$target.Add($g[$i]) }
    }
    $before = @{}
    foreach ($d in $target) { $before[$d] = Get-Rotation $d }
    if ($target.Count -gt 0) {
        foreach ($d in $target) {
            $c = Bridge @{ cmd = 'act'; guid = $d; verb = 'roll' }
        }
    }
    # roll() only STARTS the roll; poll until each die has MOVED AWAY from its pre-roll
    # orientation and then held still twice (same trick as roll.ps1 - without the
    # "moved" test the first two polls can read the PREVIOUS face).
    $faces = @{}
    $status = @{}
    foreach ($i in 0..4) {
        if ($keepSet.ContainsKey($i + 1)) { $status[$g[$i]] = 'keep' } else { $status[$g[$i]] = 'rolling' }
    }
    $hits = @{}
    $prev = @{}
    $moved = @{}
    $deadline = (Get-Date).AddSeconds($Poll)
    while ((Get-Date) -lt $deadline) {
        $busy = $false
        foreach ($d in $target) {
            if ($status[$d] -eq 'settled') { continue }
            $busy = $true
            $rs = Get-Rotation $d
            if ($rs -eq '') { continue }
            if ((-not $moved.ContainsKey($d)) -and $rs -ne $before[$d]) { $moved[$d] = $true }
            if ($moved.ContainsKey($d) -and $prev.ContainsKey($d) -and $prev[$d] -eq $rs) {
                $hits[$d] = 1 + [int]$hits[$d]
                if ($hits[$d] -ge 2) { $status[$d] = 'settled' }
            } else { $hits[$d] = 0 }
            $prev[$d] = $rs
        }
        if (-not $busy) { break }
        Start-Sleep -Milliseconds 250
    }
    for ($i = 0; $i -lt 5; $i++) {
        $d = $g[$i]
        if ($status[$d] -eq 'keep') { continue }
        $faces[$i + 1] = Get-Face $d $seat
    }
    return @{ faces = $faces; status = $status; guids = $g }
}

# --------------------------------------------------------------- the matcher -----
# A skill's "match" is either
#   { require = {SYM = n, ...} }  -- at least n of each; every other symbol must be in
#                                    "allowed" (so an ability that needs 5 of a set
#                                    cannot be claimed off 3 of them + 2 strays)
#   { straight = 4|5 }            -- 4 or 5 CONSECUTIVE face numbers
#   { distinct = 4 }              -- at least 4 different face numbers
# Symbol "moon+star" (the moon elf's 6) is ambiguous: it can count as the moon or the
# star, one die at a time. Resolve-Alt() enumerates those assignments and asks whether
# ANY assignment satisfies the requirement. No assignment is invented silently - if
# none works, the ability simply does not match.
# Exact, not clever: brute-force the ambiguity by trying every split of the ambiguous
# dice into "moon" vs "star", and ask whether ANY split satisfies the requirement.
function Face-Counts([hashtable]$faces) {
    $c = @{}
    foreach ($i in 1..5) {
        if (-not $faces.ContainsKey($i)) { continue }
        $k = [string]([int]$faces[$i])
        if ($c.ContainsKey($k)) { $c[$k] = $c[$k] + 1 } else { $c[$k] = 1 }
    }
    return $c
}

function Symbol-Counts([string]$seat, [hashtable]$faces) {
    $c = @{}
    foreach ($i in 1..5) {
        if (-not $faces.ContainsKey($i)) { continue }
        $sym = Symbol-Of $seat ([int]$faces[$i])
        if ($c.ContainsKey($sym)) { $c[$sym] = $c[$sym] + 1 } else { $c[$sym] = 1 }
    }
    return $c
}
