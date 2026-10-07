# play.ps1 - Dice Throne: ONE COMMAND PER ROUND.
#
# WHY THIS EXISTS
#   Mid-game the main agent's context fills up, so every turn used to cost either a
#   sub-agent spawn or a re-read of the rulebook. This script ends that: it carries the
#   per-game constants (counters, dice, symbols, skill table) and the TTS transport in
#   one process, and prints at most a few lines per command.
#
# USAGE (ASCII only on the command line; Chinese lives in the data file)
#   play.ps1 status
#   play.ps1 income  -Seat moon
#   play.ps1 roll    -Seat moon [-Lock 1,3] [-NoRoll] [-Tries 1]
#   play.ps1 attack  -Seat moon -Ability '<name>' [-Apply] [-Damage N] [-Idx K]
#   play.ps1 defense -Seat scar [-Roll] [-NoRoll] [-Apply -Incoming N] [-DamageOverride N]
#   play.ps1 say     -TextFile <utf8 file>
#
# ERROR CODES (each one is a DIFFERENT fault and must never be blurred)
#   NO PART  : the data file cache\dicethrone_rules.json is missing or unreadable
#   BAD DATA : a counter / a reply / the data file could not be parsed. Hard stop.
#   NO PORT  : 127.0.0.1:39999 refused (and 39998 free) -> TTS is not listening
#   NO REPLY : connected, but no messageID 4 came back in time
#   BUSY     : 127.0.0.1:39998 is held by another listener (channel_watch) -> retry
#   LOOKUP   : the data table has no such ability / no matcher for that seat
#
# IRON RULE: every write to HP/CP is read back and the read-back is printed. A write
#   whose read-back disagrees is reported as BAD DATA, never smoothed over.
#
# ASCII only outside comments and the few Chinese strings that ARE the game's own names.
# Requires the UTF-8 BOM: run tts\check_ps1.ps1 after any edit.

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'income', 'roll', 'attack', 'defense', 'say')]
    [string]$Action = 'status',

    [ValidateSet('moon', 'scar')]
    [string]$Seat = 'moon',

    [string]$Ability = '',

    [int[]]$Lock = @(),
    [int]$Tries = 0,
    [switch]$Roll,
    [switch]$NoRoll,
    [switch]$Apply,
    [int]$Incoming = 0,
    [int]$Damage = -1,
    [int]$Idx = -1,
    [int]$Poll = 25,
    [string]$TextFile = '',
    [string]$RulesFile = '',
    [string]$TtsLib = '',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ($RulesFile -eq '') { $RulesFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'cache\dicethrone_rules.json' }
if ($TtsLib -eq '') { $TtsLib = Join-Path $PSScriptRoot 'ttslib.ps1' }

# ------------------------------------------------------------------ failures -----
# Every exit says WHY in one line, and never invents a value.
function Fail([string]$code, [string]$msg) {
    Write-Host ("{0} {1}" -f $code, $msg)
    exit 1
}

# ------------------------------------------------------------------ plumbing -----
if (-not (Test-Path -LiteralPath $TtsLib)) { Fail 'NO PART' ("ttslib.ps1 not found at " + $TtsLib) }
. $TtsLib

if (-not (Test-Path -LiteralPath $RulesFile)) { Fail 'NO PART' ("rules file not found: " + $RulesFile) }
$Raw = [System.IO.File]::ReadAllText($RulesFile, [System.Text.Encoding]::UTF8)
$Rules = $null
try { $Rules = $Raw | ConvertFrom-Json } catch { Fail 'BAD DATA' ("rules file is not valid JSON: " + $_.Exception.Message) }

# Invoke-Tts error strings -> the four codes this project distinguishes.
function Err-Code([string]$e) {
    switch ($e) {
        'LISTENERBUSY' { return 'BUSY' }      # 39998 held by a watcher: retry, do not alarm
        'PORTCLOSED' { return 'NO PORT' }     # 39999 refused
        'NOREPLY' { return 'NO REPLY' }
        default { return 'BAD DATA' }
    }
}

# One bridge command object -> the customMessage object, or die with the right code.
function Bridge($Cmd, [int]$TimeoutSec = 15) {
    $env = @{ messageID = 2; customMessage = $Cmd } | ConvertTo-Json -Depth 8 -Compress
    $r = $null
    for ($i = 1; $i -le 3; $i++) {
        $r = Invoke-Tts -Envelope $env -TimeoutSec $TimeoutSec
        if ($r.err -ne 'LISTENERBUSY') { break }
        Start-Sleep -Milliseconds 500
    }
    if ($r.err) { Fail (Err-Code $r.err) ("cmd=" + $Cmd.cmd + " (" + $r.err + ")") }
    if ($null -eq $r.custom) { Fail 'BAD DATA' ("reply from TTS was not JSON (cmd=" + $Cmd.cmd + ")") }
    if ($r.custom.ok -ne $true) {
        $e = 'unknown'
        if ($null -ne $r.custom.err) { $e = [string]$r.custom.err }
        Fail 'BAD DATA' ("cmd=" + $Cmd.cmd + " rejected by bridge: " + $e)
    }
    return $r.custom
}

function Ping-Custom { return (Bridge @{ cmd = 'ping' }) }

# Counter read: HP and CP both live in the object's script_state as {"saved_count":N}.
function Get-Counter([string]$Guid, [string]$What) {
    $c = Bridge @{ cmd = 'act'; guid = $Guid; verb = 'getScriptState' }
    $s = ''
    if ($null -ne $c.result) { $s = [string]$c.result }
    if ($s -notmatch 'saved_count"\s*:\s*(-?\d+)') {
        Fail 'BAD DATA' ("$What counter $Guid did not return saved_count (got: " + $s + ")")
    }
    return [int]$Matches[1]
}

# Counter write: setcount does desc + customSet() + script_state, then we READ IT BACK.
function Set-Counter([string]$Guid, [int]$Want, [string]$What) {
    $before = Get-Counter $Guid $What
    $c = Bridge @{ cmd = 'setcount'; guid = $Guid; value = $Want }
    $after = Get-Counter $Guid $What
    if ($after -ne $Want) {
        Fail 'BAD DATA' ("$What write did not stick: wanted $Want, read back $after (was $before, guid $Guid)")
    }
    return @{ before = $before; after = $after }
}

# ------------------------------------------------------------- tiny converters ---
function As-Int([object]$v) {
    if ($null -eq $v) { return $null }
    $s = [string]$v
    if ($s -match '^-?\d+$') { return [int]$s }
    return $null
}

function As-Dict([object]$o) {
    $d = @{}
    if ($null -eq $o) { return $d }
    foreach ($p in $o.PSObject.Properties) { $d[$p.Name] = $p.Value }
    return $d
}

# status / gain may be a plain array, a string, or an object with a "gain" list.
function As-Strings([object]$o) {
    $out = New-Object System.Collections.ArrayList
    if ($null -eq $o) { return @() }
    if ($o -is [string]) { [void]$out.Add([string]$o); return @($out) }
    if ($o.PSObject.Properties.Name -contains 'gain') { return As-Strings $o.gain }
    foreach ($x in @($o)) { if ($null -ne $x) { [void]$out.Add([string]$x) } }
    return @($out)
}

# ------------------------------------------------------------------- the dice ----
$Dice = @{
    moon = @('f0738d', '187cc1', '656b32', 'e00b2e', '910636')
    scar = @('205873', '26745c', 'aa8300', '240f79', '033d23')
}

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
function Has($o, [string]$name) {
    if ($null -eq $o) { return $false }
    return ($o.PSObject.Properties.Name -contains $name)
}

# Safe scalar read for an optional field: returns the value, or '-' when absent/null.
function Text-Of($o, [string]$name) {
    if (-not (Has $o $name)) { return '-' }
    $v = $o.$name
    if ($null -eq $v) { return '-' }
    return [string]$v
}

function Set-Lock([string]$g, [bool]$on) {
    $c = Bridge @{ cmd = 'act'; guid = $g; verb = 'setLock'; value = $on }
    $c = Bridge @{ cmd = 'act'; guid = $g; verb = 'getLock' }
    $now = [string]$c.result
    if ($on -and ($now -notmatch 'true')) { Fail 'BAD DATA' ("lock did not take on $g (getLock=" + $now + ")") }
    if ((-not $on) -and ($now -match 'true')) { Fail 'BAD DATA' ("unlock did not take on $g (getLock=" + $now + ")") }
}

function Roll-Dice([string]$seat, [int[]]$Keep, [bool]$NoRoll) {
    $g = $Dice[$seat]
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
function Match-Symbols([hashtable]$counts, $require, [int]$minSymbols) {
    $amb = 0
    if ($counts.ContainsKey('🌙')) { $amb = [int]$counts['🌙'] }
    for ($moonN = 0; $moonN -le $amb; $moonN++) {
        $starN = $amb - $moonN
        $have = @{}
        foreach ($k in $counts.Keys) {
            if ($k -eq '🌙') { continue }
            $have[$k] = [int]$counts[$k]
        }
        $have['🌙'] = $moonN
        $have['✳'] = $starN
        $ok = $true
        $matched = 0
        foreach ($p in $require.PSObject.Properties) {
            $want = As-Int $p.Value
            $got = 0
            if ($have.ContainsKey($p.Name)) { $got = [int]$have[$p.Name] }
            if ($null -eq $want) { $ok = $false; break }
            # accumulate BEFORE the failure test: a break would otherwise leave
            # $matched at 0 and silently kill the min_symbols test below.
            $matched = $matched + [int]$want
            if ($got -lt $want) { $ok = $false; break }
        }
        if (-not $ok) { continue }
        # min_symbols (from the data file) is what separates
        #   "at least N of these, the other dice are free"  (长弓: 3 bows + anything)
        # from
        #   "the whole roll must be these symbols"          (赐死射击: 5x bow/moon)
        if ($minSymbols -gt 0 -and $minSymbols -gt $matched) { continue }
        return $true
    }
    return $false
}

function Match-Ability($ability, [hashtable]$fc, [hashtable]$sc) {
    if ($null -eq $ability.match) { return $false }
    $m = $ability.match
    if ($m.PSObject.Properties.Name -contains 'require') {
        # NB: ConvertFrom-Json hands back PSCustomObject, NOT a hashtable. Everything
        # below must walk PSObject.Properties, never .Keys, or StrictMode throws.
        $req = $m.require
        $minSymbols = 0
        if ($ability.PSObject.Properties.Name -contains 'min_symbols') {
            # A JSON null survives as a real $null, and [int]$null FAILS under
            # Set-StrictMode 2.0 -- so it must be tested here, never cast blindly.
            $ms = As-Int $ability.min_symbols
            if ($null -ne $ms) { $minSymbols = [int]$ms }
        }
        $exact = $false
        if ($ability.PSObject.Properties.Name -contains 'exact_count') {
            if ($ability.exact_count -eq $true) { $exact = $true }
        }
        if ($exact) {
            # exact_count: the listed symbols must all be present and the roll must be
            # large enough to hold them (i.e. no "free" die). The four-of-a-kind rows
            # (厄运缠身 / 黑暗神书 / 星蚀 / 绝对混沌) are written this way because the
            # real board pattern is "these symbols, any 5th die".
            $total = 0
            foreach ($p in $req.PSObject.Properties) {
                $v = As-Int $p.Value
                if ($null -ne $v) { $total = $total + [int]$v }
            }
            $minSymbols = $total
        }
        return (Match-Symbols $sc $req $minSymbols)
    }
    if ($m.PSObject.Properties.Name -contains 'distinct') {
        # distinct_exact: the number of DIFFERENT faces must equal the value, AND (when
        # requiredSymbols is given) every one of those symbols must appear. Since one
        # face yields exactly one symbol, 4 distinct symbols can only come from 4
        # distinct faces - so a five-of-a-kind roll cannot fake this.
        $need = As-Int $m.distinct
        if ($null -eq $need) { return $false }
        $n = 0
        foreach ($k in $fc.Keys) { if ([int]$fc[$k] -gt 0) { $n = $n + 1 } }
        if ($n -ne $need) { return $false }
        # pattern_ok sits on the ability row in the data file; also accept it inside
        # "match" so either layout works.
        $pok = $null
        if (Has $ability 'pattern_ok') { $pok = $ability.pattern_ok }
        elseif (Has $m 'pattern_ok') { $pok = $m.pattern_ok }
        if ($null -ne $pok) {
            foreach ($p in $pok.PSObject.Properties) {
                if (-not $sc.ContainsKey($p.Name)) { return $false }
                if ([int]$sc[$p.Name] -lt 1) { return $false }
            }
        }
        return $true
    }
    if ($m.PSObject.Properties.Name -contains 'straight') {
        $need = As-Int $m.straight
        if ($null -eq $need) { return $false }
        $best = 0; $run = 0; $last = 0
        foreach ($f in (1..6)) {
            if ($fc.ContainsKey([string]$f) -and [int]$fc[[string]$f] -gt 0) {
                if ($f -eq $last + 1) { $run = $run + 1 } else { $run = 1 }
                $last = $f
                if ($run -gt $best) { $best = $run }
            }
        }
        return ($best -ge $need)
    }
    return $false
}

# Two separate count tables, on purpose:
#   Face-Counts   keys "1".."6" -- faces, for straight / distinct tests
#   Symbol-Counts keys are symbol labels, keeping the ambiguous 6 as its own label
# The moon elf's 6 is "moon+star": ONE die can be the moon OR the star, never both.
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

function Damage-Text($ability) {
    $d = $ability.damage
    if ($null -eq $d) { return 'damage=?' }
    if ($d -is [int] -or $d -is [long] -or $d -is [double]) { return ("damage=" + $d) }
    $dd = As-Dict $d
    if ($dd.Count -eq 0) { return 'damage=?' }
    $parts = @()
    foreach ($k in ($dd.Keys | Sort-Object { [int]$_ })) { $parts += ("" + $k + "->" + $dd[$k]) }
    return ("tiers " + ($parts -join '/'))
}

function Damage-Of($ability) {
    $d = $ability.damage
    if ($null -eq $d) { return $null }
    if ($d -is [int] -or $d -is [long] -or $d -is [double]) { return [int]$d }
    return $null   # tiered: no single number, callers must ask for the tier
}

function Ability-Line($ability, $counts) {
    $st = As-Strings $ability.status
    $stx = '-'
    if (@($st).Count -gt 0) { $stx = (@($st) -join '+') }
    $u = ''
    if ($ability.unconfirmed -eq $true) { $u = ' [UNCONFIRMED]' }
    $tag = ''
    if ($ability.ultimate -eq $true) { $tag = ' ULT' }
    $dmg = Damage-Text $ability $counts
    return ("{0}{1} | {2} | {3} | status={4}{5}" -f $ability.name, $tag, $ability.pattern_text, $dmg, $stx, $u)
}

function Top-Abilities([string]$seat, [hashtable]$faces, [int]$n) {
    $hero = $Rules.heroes.$seat
    $fc = Face-Counts $faces
    $sc = Symbol-Counts $seat $faces
    $list = @()
    foreach ($a in $hero.skills) {
        if (Match-Ability $a $fc $sc) { $list += $a }
    }
    if (Match-Ability $hero.ultimate $fc $sc) { $list += $hero.ultimate }
    # sort by damage, descending; tiered / unknown damage sorts below a fixed number
    $scored = @()
    foreach ($a in $list) {
        $d = Damage-Of $a
        if ($null -eq $d) { $d = -1 }
        $scored += [pscustomobject]@{ a = $a; d = $d }
    }
    $scored = @($scored | Sort-Object -Property @{ Expression = 'd'; Descending = $true }, @{ Expression = { $_.a.name }; Descending = $false })
    $out = @()
    foreach ($s in @($scored)) { if (@($out).Count -lt $n) { $out += $s.a } }
    return @{ all = @($scored); top = $out; counts = $sc }
}

# ---------------------------------------------------------- command: status ------
function Cmd-Status {
    $p = Ping-Custom
    $mHP = Get-Counter (Seat-Obj 'moon').hp_counter 'moon HP'
    $mCP = Get-Counter (Seat-Obj 'moon').cp_counter 'moon CP'
    $sHP = Get-Counter (Seat-Obj 'scar').hp_counter 'scar HP'
    $sCP = Get-Counter (Seat-Obj 'scar').cp_counter 'scar CP'
    # Status tokens = the live objects sitting on the two status bars. The bars are at
    # z=48 (moon x 18..34, scar x 56..84); reading the table this way cannot touch the
    # player's hand (x 55-125 / z -105..-85 / y>7.5 is a different z band entirely).
    $tok = @{ moon = '?'; scar = '?' }
    try {
        $idx = Bridge @{ cmd = 'index'; limit = 200 } 40
        $items = @()
        if ($null -ne $idx.items) {
            if ($idx.items -is [string]) { $items = @($idx.items | ConvertFrom-Json) }
            else { $items = @($idx.items) }
        }
        $mnames = @(); $snames = @()
        $items = @($items)
    foreach ($it in $items) {
            # NULL-SAFE: with Set-StrictMode 2.0, touching $it.z on an item that has no
            # z throws. Items are PSCustomObjects parsed out of a nested JSON string.
            if ($null -eq $it) { continue }
            $zn = $it.PSObject.Properties.Name
            if (($zn -notcontains 'z') -or ($zn -notcontains 'x') -or ($zn -notcontains 'name')) { continue }
            $z = [double]$it.z
            $x = [double]$it.x
            if ([Math]::Abs($z - 48) -gt 0.5) { continue }
            $nm = [string]$it.name
            if ($x -ge 16 -and $x -le 35) { $mnames += $nm }
            elseif ($x -ge 55 -and $x -le 85) { $snames += $nm }
        }
        if ($mnames.Count -gt 0) { $tok.moon = ($mnames -join ',') }
        elseif (@($items).Count -eq 0) { $tok.moon = 'BAD-DATA(index empty)' }
        else { $tok.moon = 'none-on-bar' }
        if ($snames.Count -gt 0) { $tok.scar = ($snames -join ',') }
        elseif (@($items).Count -eq 0) { $tok.scar = 'BAD-DATA(index empty)' }
        else { $tok.scar = 'none-on-bar' }
    } catch {
        $tok.moon = 'UNKNOWN(index failed)'
        $tok.scar = 'UNKNOWN(index failed)'
    }
    Write-Host ("status objs={0} moonHP={1} moonCP={2} scarHP={3} scarCP={4} bridge={5}" -f $p.objects, $mHP, $mCP, $sHP, $sCP, $p.v)
    Write-Host ("tokens moon: {0} | scar: {1}" -f $tok.moon, $tok.scar)
}

# ---------------------------------------------------------- command: income ------
function Cmd-Income {
    $cp = (Seat-Obj $Seat).cp_counter
    $r = Set-Counter $cp (((Get-Counter $cp ($Seat + ' CP')) + 1)) ($Seat + ' CP')
    Write-Host ("income {0} CP {1}->{2} (read back {2}, counter {3})" -f $Seat, $r.before, $r.after, $cp)
}

# ------------------------------------------------------------ command: roll ------
function Cmd-Roll {
    $g = Roll-Dice $Seat $Lock ([bool]$NoRoll)
    $faces = $g.faces
    $num = @(); $sym = @(); $unsettled = 0
    foreach ($i in 1..5) {
        if (-not $faces.ContainsKey($i)) { $num += ("{0}=?" -f $i); continue }
        $f = [int]$faces[$i]
        $num += ("{0}={1}" -f $i, $f)
        $sym += (Symbol-Of $Seat $f)
        if ($g.status[$g.guids[$i - 1]] -eq 'not-settled') { $unsettled++ }
    }
    $lockTxt = '-'
    if (@($Lock).Count -gt 0) { $lockTxt = (@($Lock) -join ',') }
    $extra = ''
    if ($unsettled -gt 0) { $extra = (" WARN not-settled=" + $unsettled) }
    Write-Host ("roll {0} lock={1} faces {2}{3}" -f $Seat, $lockTxt, ($num -join ' '), $extra)
    Write-Host ("     symbols {0}" -f ($sym -join ''))
    $res = Top-Abilities $Seat $faces 3
    if (@($res.top).Count -eq 0) {
        Write-Host ("NO SKILL (can reroll / lock dice; tries used unknown, pass -Tries). All skill rows are in cache\dicethrone_rules.json")
    } else {
        foreach ($a in @($res.top)) { Write-Host ("  -> " + (Ability-Line $a $res.counts)) }
    }
}

# ---------------------------------------------------------- command: attack ------
function Find-Ability([string]$seat, [string]$name, [int]$idx) {
    $hero = $Rules.heroes.$seat
    $want = $name.Trim()
    # accept either bracket style: the board writes 打不到我（防御）, a shell often types ()
    $want = $want.Replace('(', '（').Replace(')', '）')
    $hits = @()
    foreach ($a in $hero.skills) {
        $n = ([string]$a.name).Replace('(', '（').Replace(')', '）')
        if ($n -eq $want) { $hits += $a }
    }
    $un = ([string]$hero.ultimate.name).Replace('(', '（').Replace(')', '）')
    if ($un -eq $want) { $hits += $hero.ultimate }
    $dn = ([string]$hero.defense.name).Replace('(', '（').Replace(')', '）')
    if ($dn -eq $want) { $hits += $hero.defense }
    if ($hits.Count -eq 0) { Fail 'LOOKUP' ("no ability named '" + $name + "' for seat " + $seat) }
    if ($hits.Count -gt 1 -and $idx -lt 0) {
        $names = @()
        foreach ($h in $hits) { $names += ([string]$h.pattern_text) }
        Fail 'LOOKUP' ("'" + $name + "' is ambiguous for seat " + $seat + " (" + ($names -join ' / ') + ") -- pass -Idx 0.." + ($hits.Count - 1))
    }
    if ($idx -ge 0) {
        if ($idx -ge $hits.Count) { Fail 'LOOKUP' ("-Idx " + $idx + " out of range for '" + $name + "' (0.." + ($hits.Count - 1) + ")") }
        return $hits[$idx]
    }
    return $hits[0]
}

function Apply-Damage([string]$seat, [int]$n) {
    $who = if ($seat -eq 'moon') { 'scar' } else { 'moon' }
    $hp = (Seat-Obj $who).hp_counter
    $r = Set-Counter $hp (((Get-Counter $hp ($who + ' HP')) - $n) ) ($who + ' HP')
    Write-Host ("HP {0} {1}->{2} (-{3}, read back {2})" -f $who, $r.before, $r.after, $n)
}

function Cmd-Attack {
    $a = Find-Ability $Seat $Ability $Idx
    Write-Host ("attack {0} '{1}' | dice {2} | {3} | status={4} | defendable={5} | extraRoll={6}" -f `
        $Seat, $a.name, (Text-Of $a 'pattern_text'), (Damage-Text $a), ((As-Strings $a.status) -join '+'), (Text-Of $a 'defendable'), (Text-Of $a 'extra_roll'))
    Write-Host ("effect: {0}" -f (Text-Of $a 'display'))
    if ($a.conflict) { Write-Host ("conflict: {0}" -f $a.conflict) }
    if ($a.unconfirmed -eq $true) { Write-Host ("UNCONFIRMED: this row has unread or contradictory numbers -- do not treat it as settled") }
    if ($Apply) {
        $dmg = $Damage
        if ($dmg -lt 0) {
            $auto = Damage-Of $a
            if ($null -eq $auto) { $dmg = -1 } else { $dmg = [int]$auto }
        }
        if ($dmg -lt 0) {
            Fail 'BAD DATA' ("this ability has no single base damage (tiered or conditional) -- pass -Damage N explicitly")
        }
        Apply-Damage $Seat $dmg
    } else {
        Write-Host ("(not applied -- default. After the defender rolls, re-run with -Apply [-Damage N])")
    }
}

# --------------------------------------------------------- command: defense ------
function Cmd-Defense {
    $doRoll = $true
    if ($NoRoll) { $doRoll = $false }
    if (-not $Roll -and -not $NoRoll) {
        # Default is READ-ONLY: during a live turn we must not disturb the table.
        Write-Host ("defense {0} read-only (pass -Roll to actually throw the dice)" -f $Seat)
        $doRoll = $false
    }
    $g = Roll-Dice $Seat @() (-not $doRoll)
    $faces = $g.faces
    $num = @()
    foreach ($i in 1..5) { if ($faces.ContainsKey($i)) { $num += ("{0}={1}" -f $i, $faces[$i]) } }
    Write-Host ("defense {0} faces {1}" -f $Seat, ($num -join ' '))
    $hero = $Rules.heroes.$Seat
    $def = $hero.defense
    $counts = Symbol-Counts $Seat $faces
    $reduction = 0
    $counter = 0
    $notes = @()
    if ($null -ne $def.reduce) {
        $sym = [string]$def.reduce.symbol
        $have = 0
        if ($counts.ContainsKey($sym)) { $have = [int]$counts[$sym] }
        $pairs = [int][Math]::Floor($have / 2)
        if ($def.reduce.type -eq 'halfPerPair') { $reduction = $pairs }
        $notes += ("{0}x{1} -> {2} half-reduction instance(s); pairs only, an odd leftover {1} does nothing" -f $have, $sym, $pairs)
    }
    if ($null -ne $def.counter) {
        $sym = [string]$def.counter.symbol
        $have = 0
        if ($counts.ContainsKey($sym)) { $have = [int]$counts[$sym] }
        $pairs = [int][Math]::Floor($have / 2)
        $amt = As-Int $def.counter.amount
        if ($null -eq $amt) { $amt = 0 }
        $counter = $pairs * $amt
        $notes += ("{0}x{1} -> {2} damage back (pairs only)" -f $have, $sym, $counter)
    }
    $gr = $null
    if (Has $def 'grants') { $gr = $def.grants }
    if ($null -ne $gr) {
        foreach ($k in $gr.PSObject.Properties.Name) { $notes += ($k + " -> " + $gr.$k) }
    }
    if ((Has $def 'unconfirmed') -and ($def.unconfirmed -eq $true)) { $notes += 'UNCONFIRMED defense row (sources disagree)' }
    Write-Host ("defense {0} rule: {1}" -f $Seat, (($notes) -join '; '))
    if ($Apply) {
        if ($Incoming -le 0) { Fail 'BAD DATA' ("-Apply needs -Incoming <damage>") }
        # half damage, rounded UP, once per reduction instance
        $final = $Incoming
        for ($i = 0; $i -lt $reduction; $i++) { $final = [int][Math]::Ceiling($final / 2.0) }
        $attacker = if ($Seat -eq 'moon') { 'scar' } else { 'moon' }
        if ($Damage -ge 0) { $final = $Damage }
        Write-Host ("resolve incoming={0} after {1} half-instance(s) -> {2}" -f $Incoming, $reduction, $final)
        Apply-Damage $attacker $final
        if ($counter -gt 0) { Apply-Damage $Seat $counter }
    } else {
        Write-Host ("(not applied -- pass -Apply -Incoming N to settle; half damage is rounded up. -Apply really writes HP.)")
    }
}

# ------------------------------------------------------------- command: say ------
function Cmd-Say {
    if ($TextFile -eq '') { Fail 'BAD DATA' ("say needs -TextFile <utf8 file>") }
    if (-not (Test-Path -LiteralPath $TextFile)) { Fail 'BAD DATA' ("no such text file: " + $TextFile) }
    $say = Join-Path $PSScriptRoot 'say.ps1'
    if (-not (Test-Path -LiteralPath $say)) { Fail 'NO PART' ("say.ps1 not found at " + $say) }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $say -MessageFile $TextFile 2>&1
    $txt = ($out | Out-String)
    if ($txt -notmatch 'ok tabwrite') { Fail 'BAD DATA' ("say.ps1 did not confirm the write: " + ($txt.Trim())) }
    Write-Host ("say ok (" + (($out | Select-Object -Last 1).ToString().Trim()) + ")")
}

function Cmd-SelfTest {
    Write-Host "selftest (offline, no TTS contact)"
    $tally = @{ bad = 0 }
    # Every case verified by hand against the face->symbol map in dicethrone_rules.json:
    #   moon: 1/2/3=bow  4/5=foot  6=moon(+star, one at a time)
    #   scar: 1/2/3=swirl  4=star  5=blood  6=M
    $cases = @(
        @{ seat = 'moon'; faces = @(1, 2, 2, 4, 4); name = '长弓'; want = $true },      # bow 3
        @{ seat = 'moon'; faces = @(1, 1, 4, 4, 4); name = '长弓'; want = $false },     # bow 2
        @{ seat = 'moon'; faces = @(1, 2, 3, 3, 3); name = '长弓'; want = $true },      # bow 5
        @{ seat = 'moon'; faces = @(6, 6, 6, 6, 2); name = '星蚀'; want = $true },      # moon 4
        @{ seat = 'moon'; faces = @(6, 6, 6, 6, 6); name = '星蚀'; want = $true },      # moon 5 also fires
        @{ seat = 'moon'; faces = @(6, 6, 6, 1, 1); name = '星蚀'; want = $false },     # moon 3
        @{ seat = 'moon'; faces = @(1, 2, 3, 4, 5); name = '缠绕射击'; want = $true },  # 4 connected
        @{ seat = 'moon'; faces = @(1, 2, 3, 4, 6); name = '缠绕射击'; want = $true },
        @{ seat = 'moon'; faces = @(1, 2, 3, 4, 5); name = '致盲射击'; want = $true },  # 5 connected
        @{ seat = 'moon'; faces = @(1, 2, 3, 4, 6); name = '致盲射击'; want = $false },
        @{ seat = 'moon'; faces = @(2, 3, 6, 6, 1); name = '赐死射击'; want = $true },  # bow 3 + moon 2
        @{ seat = 'moon'; faces = @(2, 3, 1, 1, 1); name = '赐死射击'; want = $false }, # bow 5
        @{ seat = 'moon'; faces = @(6, 6, 6, 6, 6); name = '月盈则食'; want = $true },  # moon 5
        @{ seat = 'moon'; faces = @(6, 6, 6, 6, 5); name = '月盈则食'; want = $false },
        @{ seat = 'moon'; faces = @(1, 1, 4, 4, 4); name = '隐蔽射击'; want = $true },  # bow 2 + foot 3
        @{ seat = 'moon'; faces = @(6, 1, 4, 4, 4); name = '隐蔽射击'; want = $false },
        @{ seat = 'scar'; faces = @(1, 1, 4, 4, 5); name = '厄运缠身'; want = $false }, # extra blood symbol
        @{ seat = 'scar'; faces = @(1, 1, 1, 4, 4); name = '厄运缠身'; want = $false }, # swirl 3
        @{ seat = 'scar'; faces = @(1, 1, 4, 5, 5); name = '厄运缠身'; want = $false }, # star 1
        @{ seat = 'scar'; faces = @(1, 1, 1, 1, 1); name = '魔法球'; want = $true },    # swirl 5
        @{ seat = 'scar'; faces = @(1, 1, 1, 6, 6); name = '绝对混沌'; want = $false }, # M 2
        @{ seat = 'scar'; faces = @(6, 6, 6, 6, 5); name = '绝对混沌'; want = $true },  # M 4
        @{ seat = 'scar'; faces = @(1, 2, 4, 5, 6); name = '心灵震撼'; want = $false }, # 5 different faces
        @{ seat = 'scar'; faces = @(1, 4, 5, 6, 2); name = '心灵震撼'; want = $false }, # 5 different faces
        @{ seat = 'scar'; faces = @(1, 1, 4, 5, 5); name = '心灵震撼'; want = $false }, # 3 faces, no M
        @{ seat = 'scar'; faces = @(6, 6, 6, 6, 6); name = '汝命休矣'; want = $true },  # M 5
        @{ seat = 'scar'; faces = @(1, 2, 3, 4, 5); name = '改变现实'; want = $true }   # 4 connected
    )
    foreach ($c in $cases) {
        $seat = [string]$c.seat
        $f = @{}
        for ($i = 0; $i -lt 5; $i++) { $f[$i + 1] = [int]$c.faces[$i] }
        $fc = Face-Counts $f
        $sc = Symbol-Counts $seat $f
        $ability = $null
        foreach ($a in $Rules.heroes.$seat.skills) { if ($a.name -eq $c.name) { $ability = $a } }
        if ($null -eq $ability) {
            if ($Rules.heroes.$seat.ultimate.name -eq $c.name) { $ability = $Rules.heroes.$seat.ultimate }
        }
        if ($null -eq $ability) { Fail 'LOOKUP' ("selftest: no ability " + $c.name) }
        $got = Match-Ability $ability $fc $sc
        $mark = 'ok'
        if ($got -ne [bool]$c.want) { $mark = 'FAIL'; $tally.bad = $tally.bad + 1 }
        $sym = @()
        foreach ($i in 1..5) { $sym += (Symbol-Of $seat $f[$i]) }
        Write-Host ("  {0} {1} faces {2} sym {3} {4} -> {5} (want {6})" -f $mark, $seat, (($c.faces) -join ''), ($sym -join ''), $c.name, $got, [bool]$c.want)
    }
    Write-Host ("selftest: " + $tally.bad + " mismatch(es)")
    if ($tally.bad -gt 0) { exit 1 }
}

# ------------------------------------------------------------------- dispatch ----
switch ($Action) {
    'status' { Cmd-Status }
    'income' { Cmd-Income }
    'roll' { Cmd-Roll }
    'attack' { if ($Ability -eq '') { Fail 'LOOKUP' 'attack needs -Ability <name from cache\dicethrone_rules.json>' } ; Cmd-Attack }
    'defense' { Cmd-Defense }
    'say' { Cmd-Say }
}
if ($SelfTest) { Cmd-SelfTest }
