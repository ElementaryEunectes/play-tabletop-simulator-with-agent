# tts\lib\play.rules.ps1 - split out of play.ps1 (2026-10-08) so it can be READ on its own.
# play.ps1 dot-sources this: SAME process, no extra PowerShell start-up (0.35 s each). Never spawn it.

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
