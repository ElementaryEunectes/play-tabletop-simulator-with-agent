# tts\lib\play.verbs.ps1 - split out of play.ps1 (2026-10-08) so it can be READ on its own.
# play.ps1 dot-sources this: SAME process, no extra PowerShell start-up (0.35 s each). Never spawn it.

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
    # Income is a WRITE (+1 CP), so it takes the same guard as attack/defense: -Apply to commit,
    # -WhatIf to preview. A read-only default is not pedantry here -- a baseline benchmark once
    # called this verb while meaning to "look at the board" and silently added 1 CP to a
    # suspended match.
    $cp = (Seat-Obj $Seat).cp_counter
    $before = Get-Counter $cp ($Seat + ' CP')
    $want = $before + 1
    if (-not $Apply) {
        Write-Host ("income {0} CP {1} -> {2} (READ-ONLY: pass -Apply to write)" -f $Seat, $before, $want)
        return
    }
    Write-Host ("WILL WRITE  CP {0} {1} -> {2}" -f $Seat, $before, $want)
    if ($WhatIfPreference) {
        Write-Host ("WHATIF: nothing written, {0} CP stays {1}" -f $Seat, $before)
        return
    }
    $r = Set-Counter $cp $want ($Seat + ' CP')
    Write-Host ("income {0} CP {1}->{2} (read back {2}, counter {3})" -f $Seat, $r.before, $r.after, $cp)
    if ([int]$r.after -ne [int]$want) { Fail 'BAD DATA' ("read-back mismatch: asked for {0} CP {1}, the table says {2}" -f $Seat, $want, $r.after) }
}

# ------------------------------------------------------------ command: roll ------
function Cmd-Roll {
    $doRoll = $true
    if ($NoRoll) { $doRoll = $false }
    if (-not $Roll -and -not $NoRoll) {
        # Default is READ-ONLY, exactly like Cmd-Defense. It used to throw the dice, so a bare
        # "play.ps1 roll" destroyed the very faces somebody was asking about. Pass -Roll to throw.
        Write-Host ("roll {0} read-only (pass -Roll to actually throw the dice)" -f $Seat)
        $doRoll = $false
    }
    $g = Roll-Dice $Seat $Lock (-not $doRoll)
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
        Write-Host ("NO SKILL (can reroll / lock dice; tries used unknown, pass -Tries). All skill rows come from the game's rules JSON")
    } else {
        foreach ($a in @($res.top)) { Write-Host ("  -> " + (Ability-Line $a $res.counts)) }
    }
}

# ---------------------------------------------------------- command: attack ------
function Apply-Damage([string]$seat, [int]$n) {
    $who = if ($seat -eq 'moon') { 'scar' } else { 'moon' }
    $hp = (Seat-Obj $who).hp_counter
    $before = Get-Counter $hp ($who + ' HP')
    $want = $before - $n
    # Announce the exact write BEFORE making it. The damage number is usually the thing still
    # being argued about, so a preview that touches nothing (-WhatIf) is cheap insurance.
    Write-Host ("WILL WRITE  HP {0} {1} -> {2}  (-{3})" -f $who, $before, $want, $n)
    if ($WhatIfPreference) {
        Write-Host ("WHATIF: nothing written, {0} HP stays {1}" -f $who, $before)
        return
    }
    $r = Set-Counter $hp $want ($who + ' HP')
    Write-Host ("HP {0} {1}->{2} (-{3}, read back {2})" -f $who, $r.before, $r.after, $n)
    if ([int]$r.after -ne [int]$want) { Fail 'BAD DATA' ("read-back mismatch: asked for {0} HP {1}, the table says {2}" -f $who, $want, $r.after) }
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

# ------------------------------------------------------------ command: turn ------
# ONE call to open a turn, instead of status + roll + tabread. Every invocation of this file
# costs a fresh PowerShell start (~0.35s) plus its TTS round trips, so folding the three reads
# together is the cheapest per-turn saving there is. It is strictly READ-ONLY: the dice are
# read, never thrown (see the -Roll/-NoRoll guardrail in roll.ps1), and the notebook is only
# echoed, never written.
function Cmd-Turn {
    Cmd-Status
    $g = Roll-Dice 'moon' @() $true                    # NoRoll = touch nothing
    $faces = $g.faces
    $num = @(); $sym = @()
    foreach ($i in 1..5) {
        if (-not $faces.ContainsKey($i)) { $num += ("{0}=?" -f $i); continue }
        $f = [int]$faces[$i]
        $num += ("{0}={1}" -f $i, $f)
        $sym += (Symbol-Of 'moon' $f)
    }
    Write-Host ("moon dice {0}  symbols {1}" -f ($num -join ' '), ($sym -join ''))
    $res = Top-Abilities 'moon' $faces 3
    if (@($res.top).Count -eq 0) { Write-Host "  (no matching skill)" }
    else { foreach ($a in @($res.top)) { Write-Host ("  -> " + (Ability-Line $a $res.counts)) } }
    $t = Bridge @{ cmd = 'tabread' } 10 -Soft
    if ($null -ne $t) {
        $body = ''
        if ($null -ne $t.PSObject.Properties['body']) { $body = [string]$t.body }
        if ($body.Trim() -ne '') {
            $tail = $body.Substring([Math]::Max(0, $body.Length - 160))
            Write-Host ("notebook> " + (($tail -replace '\s+', ' ').Trim()))
        } else { Write-Host "notebook> (empty)" }
    } else { Write-Host "notebook> (unreadable, ignored)" }
}

function Cmd-SelfTest {
    Write-Host "selftest (offline, no TTS contact)"
    $tally = @{ bad = 0 }
    # Every case verified by hand against the face->symbol map in the game's rules JSON:
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
