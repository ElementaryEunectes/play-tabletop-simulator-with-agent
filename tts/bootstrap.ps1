# bootstrap.ps1 - turn a fresh obj_index.csv into a session map, using THE GAME'S OWN data file.
#
# WHY THIS EXISTS
#   Everything that is a *guid* is bound to ONE save file. Open the mod again and every guid changes.
#   What does NOT change is the mod's own data: image hashes, the nicknames the mod itself sets,
#   scales, and the left-to-right seat order. So identification is done by THOSE, never by
#   remembered guids.
#
# WHAT CHANGED 2026-10-09 (and why)
#   This script used to carry the recognition tables IN CODE for the one game it was written for
#   (a campaign that has since finished): "哥伦比亚金券", the 源石/源岩/异铁 image hashes, the event
#   deck hashes, 移动城市, the enterprise-board CardID legend. That is game data, so on any other
#   mod those tables matched nothing - and the script kept printing an empty map as if that were
#   the answer. The tables now live in
#       local\games\<game>\objects.json        (schema: tts\docs\BOOTSTRAP.md, section objects.json)
#   and this script is the generic RENDERER: seats from the HandTrigger zones, then one section per
#   entry that file declares. With no file it stops, names the path it wanted, and prints the
#   command that produces the raw material for writing it (-Inventory).
#
# USAGE
#   powershell -File tts\bootstrap.ps1 -Inventory   # what IS on the table: name / nick / hash histogram
#   powershell -File tts\bootstrap.ps1              # -> cache\session_map.md; stdout = seat table + summary
#   powershell -File tts\bootstrap.ps1 -Full        # also print the whole map to stdout
#   powershell -File tts\bootstrap.ps1 -Objects <path> -Index <path> -Out <path>
# NOTE: param() must stay the FIRST statement here, and every default is backfilled AFTER
#       config.ps1 is dot-sourced (a default cannot reference config variables - they are not
#       evaluated yet - and an empty path silently wrote nothing; that cost a whole session once).
# NOTE: the failure paths use `exit 1`, not `return 1`: this is a terminal CLI tool whose stdout is
#       the report, so it must not print a stray exit code into it. An in-process `&` caller still
#       gets the code (measured: a script FILE's `exit` is caught at that file's boundary, and the
#       caller reads $LASTEXITCODE). Scripts whose output a caller MERGES with `6>&1` (diff_index,
#       live_index, ds) are the ones that must not exit - see diff_index.ps1's header.
param(
    [string]$Index = '',
    [string]$Objects = '',
    [string]$Out = '',
    [string]$InventoryOut = '',
    [switch]$Inventory,
    [switch]$Full
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($Index -eq '') { $Index = (Join-Path $DshCache 'obj_index.csv') }
if ($Out   -eq '') { $Out   = (Join-Path $DshCache 'session_map.md') }
if ($InventoryOut -eq '') { $InventoryOut = (Join-Path $DshCache 'obj_inventory.md') }
if ($Objects -eq '') { $Objects = $DshGameObjects }

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Index)) { Write-Host ("ERR no index; run obj_index.ps1 first ({0})" -f $Index); exit 1 }
# Read as UTF-8 EXPLICITLY rather than letting Import-Csv guess from a BOM: obj_index.ps1 writes a
# BOM, but a hand-made or hand-edited index may not, and a nickname read as ANSI is mojibake that
# silently matches nothing. The @(...) matters: a one-row index would otherwise arrive as a bare
# object and `.Count` on it is not 1 (see the Sort-Rows note below).
$rows = @([System.IO.File]::ReadAllLines($Index, [System.Text.Encoding]::UTF8) | ConvertFrom-Csv)

# --- helpers -------------------------------------------------------------------------------
function H8($v) { $s = "$v"; if ($s.Length -ge 8) { return $s.Substring(0, 8) } else { return $s } }
# An index cell can legitimately be EMPTY (a plain block has no url, a deck's row has no scale),
# and `[double]''` throws - which under $ErrorActionPreference='Stop' aborts the whole map. Read
# every number through this.
function Num($v) { $d = 0.0; if ([double]::TryParse("$v", [ref]$d)) { return $d } else { return 0.0 } }
# JSON property access that survives a missing key. A config file written by hand WILL have keys
# missing, and "some key I did not expect is absent" must not be a crash.
function Prop($o, [string]$name) {
    if ($null -eq $o) { return $null }
    $p = $o.PSObject.Properties[$name]
    if ($p) { return $p.Value }
    return $null
}
# An absent JSON array arrives as $null, and @($null) is a ONE-element array holding $null - which
# silently produces a spurious seat warning / an empty table header. Everything that wants a list
# goes through this. Callers wrap the RESULT in @() as well: `return @($x)` unrolls a one-element
# array back into a scalar.
function Arr($v) { if ($null -eq $v) { return @() } return @($v) }
# Markdown inline code (a literal backtick pair). Written with single quotes on purpose: inside a
# DOUBLE-quoted string a backtick starts an escape sequence, so "`{1}`" silently eats the backticks
# and merely formats - the first version of this file lost every code span that way.
function Code($s) { return ('`' + "$s" + '`') }
# NOTE ON .Count: `return @($list | Sort-Object ...)` UNROLLS a one-element array into a scalar, and
# a scalar PSCustomObject's .Count is $null - not 1. `if ($refRows.Count -gt 0)` then silently took
# the "not found" branch with a perfectly good row in hand. Every call site below wraps the result
# in @() again, and a one-element result is the NORMAL case on a real table (one board, one deck).
function Sort-Rows($list, [string]$key) {
    switch ("$key") {
        'z'    { return @($list | Sort-Object { Num $_.z }) }
        'y'    { return @($list | Sort-Object { Num $_.y }) }
        'size' { return @($list | Sort-Object { Num $_.sx }) }
        default { return @($list | Sort-Object { Num $_.x }) }
    }
}
function Pos($r) { return ("({0:N2}, {1:N2})" -f (Num $r.x), (Num $r.z)) }

# --- -Inventory: the raw material for writing objects.json ---------------------------------
# Deliberately needs NO objects.json - this is what you run on a mod nobody has taught the toolkit
# yet. Hashes are the first 8 hex of the url tail (that is what obj_index.ps1 writes into its `url`
# column), nicknames are what the mod itself sets, names say what KIND of object it is.
if ($Inventory) {
    $lines = New-Object System.Collections.ArrayList
    $add = { param($t) [void]$lines.Add($t) }
    & $add ("# obj_index inventory - {0} ({1} rows)" -f (Split-Path $Index -Leaf), $rows.Count)
    & $add ""
    & $add "> 写 objects.json 的原料：**name** 决定 kind，**nick** 多半是 mod 自己起的角色名，"
    & $add "> **hash** = url 前 8 位十六进制（牌堆 / 棋子 / 计数器都靠它认，换存档不变）。"
    & $add ""
    foreach ($spec in @(@('name', '名字 (name)'), @('nick', '昵称 (nick)'))) {
        $key = $spec[0]
        & $add ("## {0} 直方图" -f $spec[1])
        & $add ""
        $groups = @($rows | Where-Object { "$($_.$key)" -ne '' } | Group-Object { "$($_.$key)" } | Sort-Object -Property Count -Descending)
        foreach ($g in $groups) { & $add ("- {0}  x{1}" -f $g.Name, $g.Count) }
        & $add ""
    }
    & $add "## 图 hash 直方图（url 前 8 位）"
    & $add ""
    $byHash = @($rows | Where-Object { (H8 $_.url) -ne '' } | Group-Object { (H8 $_.url).ToUpperInvariant() } | Sort-Object -Property Count -Descending)
    foreach ($g in $byHash) {
        $sample = @($g.Group | Select-Object -First 1)[0]
        $nick = ''; if ("$($sample.nick)" -ne '') { $nick = (" nick=" + $sample.nick) }
        & $add ("- {0}  x{1}  name={2}{3}" -f $g.Name, $g.Count, $sample.name, $nick)
    }
    if ($byHash.Count -eq 0) { & $add "- (url 列全空：这份索引没有图 url，只能按 name/nick 认物)" }
    & $add ""
    [System.IO.File]::WriteAllText($InventoryOut, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("inventory -> {0}  ({1} lines)" -f $InventoryOut, $lines.Count)
    Write-Host ("  names: {0} distinct, nicks: {1} distinct, hashes: {2} distinct" -f `
        @($rows | Group-Object { $_.name }).Count, `
        @($rows | Where-Object { "$($_.nick)" -ne '' } | Group-Object { $_.nick }).Count, `
        $byHash.Count)
    Write-Host "  read it, fill in local\games\<game>\objects.json (schema: tts\docs\BOOTSTRAP.md), then re-run without -Inventory."
    return
}

if ($Objects -eq '') {
    Write-Host 'ERR no objects.json path: no current game (set GAME= in local\games\_current.md), or pass -Objects'
    exit 1
}
if (-not (Test-Path -LiteralPath $Objects)) {
    Write-Host ("ERR no objects.json for this game: {0}" -f $Objects)
    Write-Host "  it is GAME DATA (image hashes / nicknames / labels), so the toolkit cannot ship one."
    Write-Host ("  next: powershell -NoProfile -ExecutionPolicy Bypass -File '{0}' -Inventory" -f (Join-Path $PSScriptRoot 'bootstrap.ps1'))
    Write-Host "  it prints the name/nick/hash histogram to copy from; the schema is in tts\docs\BOOTSTRAP.md."
    exit 1
}
try {
    $cfg = [System.IO.File]::ReadAllText($Objects, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
} catch {
    Write-Host ("ERR objects.json is not valid JSON: {0}  ({1})" -f $Objects, $_.Exception.Message)
    exit 1
}

# The accumulator is called $map, NOT $L: PowerShell variable names are CASE-INSENSITIVE, so a
# loop variable `$l` somewhere below IS this variable - a `foreach ($l in $labels)` silently
# replaced the ArrayList with a string and every later Emit died on "String does not contain a
# method named 'Add'". (Found by the game-data gate, not by reading the code.)
$map = New-Object System.Collections.ArrayList
# Emit always collects the markdown line for the map file, but only ALSO prints it when asked: a
# real save produced 500+ lines, and a session reading that on stdout pays ~15-20k tokens for a
# table it rarely needs in full.
function Emit($line, [switch]$Show) { [void]$map.Add($line); if ($Show -or $Full) { Write-Host $line } }
function Note($n) {
    # `note` is one string or an array of strings; either way they are just markdown lines.
    foreach ($ln in (Arr $n)) { if ("$ln" -ne '') { Emit "$ln" } }
}
function Test-Match($row, $w) {
    if ($null -eq $w) { return $true }
    $v = Prop $w 'name';         if ($v -and "$($row.name)" -ne "$v")           { return $false }
    $v = Prop $w 'nameRegex';    if ($v -and "$($row.name)" -notmatch "$v")     { return $false }
    $v = Prop $w 'nick';         if ($v -and "$($row.nick)" -ne "$v")           { return $false }
    $v = Prop $w 'nickRegex';    if ($v -and "$($row.nick)" -notmatch "$v")     { return $false }
    $v = Prop $w 'nickNonEmpty'; if ($v -eq $true -and "$($row.nick)" -eq '')   { return $false }
    $v = Prop $w 'topLevel';     if ($v -eq $true -and "$($row.parent)" -ne '') { return $false }
    $v = Prop $w 'urlHash';      if ($v -and (H8 $row.url).ToUpperInvariant() -ne "$v".ToUpperInvariant()) { return $false }
    $v = Prop $w 'minScale';     if ($null -ne $v -and "$v" -ne '' -and (Num $row.sx) -lt (Num $v)) { return $false }
    return $true
}
# Column headings for kind=rows, so the map reads like the rest of the handover docs.
$headMap = @{ guid = 'guid'; pos = '位置'; x = 'x'; y = 'y'; z = 'z'; scale = 'scale'; nick = '昵称'; name = '名字' }
function Get-Head($c) { if ($headMap.ContainsKey("$c")) { return $headMap["$c"] } return "$c" }

Emit ("# 本局物件对照（bootstrap.ps1 自动生成）")
Emit ("")
Emit ("> 存档索引：{0}（{1} 行）· 认物数据：{2}。**guid 只对这份存档有效**；换存档重跑本脚本。" -f `
    (Split-Path $Index -Leaf), $rows.Count, (Split-Path $Objects -Leaf))
Emit ("")

# --- seats ---------------------------------------------------------------------------------
$seatCfg    = Prop $cfg 'seats'
$seatName   = "$(Prop $seatCfg 'name')"
$seatLabels = @(Arr (Prop $seatCfg 'labels'))
$seatPlayer = "$(Prop $seatCfg 'player')"
$ht = @()
if ($seatName -ne '') {
    $zBelow = Prop $seatCfg 'zBelow'
    $htAll  = @($rows | Where-Object { $_.name -eq $seatName })
    # A mod can ship extra zones off to one side (the toolkit's first game had a stray HandTrigger
    # at z=+114). Sorting by x alone pulls that one INTO the seat order and silently shifts every
    # player, so the config may declare a z cut-off. Omitting it keeps every matching zone.
    if ($null -ne $zBelow -and "$zBelow" -ne '') { $ht = @($htAll | Where-Object { (Num $_.z) -lt (Num $zBelow) }) }
    else { $ht = @($htAll) }
}
if ($seatName -ne '' -and $seatLabels.Count -gt 0 -and $ht.Count -ne $seatLabels.Count) {
    Write-Host ("WARN {0} zones kept = {1} (labels in objects.json = {2}); total {0} on the table = {3}" -f `
        $seatName, $ht.Count, $seatLabels.Count, @($rows | Where-Object { $_.name -eq $seatName }).Count)
}
$ht = @(Sort-Rows $ht 'x')
Emit ("## 座位（桌上从左到右）") -Show
Emit ("")
Emit ("| 列 | {0} guid | x |" -f $seatName) -Show
Emit ("|---|---|---|") -Show
for ($i = 0; $i -lt [math]::Min($seatLabels.Count, $ht.Count); $i++) {
    Emit ("| **{0}** | {1} | {2:N2} |" -f $seatLabels[$i], (Code $ht[$i].guid), (Num $ht[$i].x)) -Show
}
Emit ("")
if ($seatPlayer -ne '') { Emit ("> **{0} = 玩家（我）**；列序见上表。" -f $seatPlayer) -Show }
Note (Prop $seatCfg 'note')
Emit ("")

# --- sections (everything game-specific comes from objects.json) ----------------------------
foreach ($s in (Arr (Prop $cfg 'sections'))) {
    if ($null -eq $s) { continue }
    $kind  = "$(Prop $s 'kind')"
    $title = "$(Prop $s 'title')"
    if ($title -ne '') { Emit $title; Emit "" }
    $where  = Prop $s 'where'
    $byHash = Prop $s 'byHash'
    $cols   = @(Arr (Prop $s 'columns'))
    if ($cols.Count -eq 0) { $cols = @('guid', 'pos') }
    $sort   = "$(Prop $s 'sort')"
    $hit    = @($rows | Where-Object { Test-Match $_ $where })

    switch ($kind) {
        'seatRow' {
            # One row per seat: counters, player tokens, panels - anything that exists once per seat.
            $hit = @(Sort-Rows $hit $sort)
            $withScale = ($cols -contains 'scale')
            if ($withScale) { Emit ("| 列 | guid | 位置 | scale |"); Emit ("|---|---|---|---|") }
            else            { Emit ("| 列 | guid | 位置 |");        Emit ("|---|---|---|") }
            for ($i = 0; $i -lt $hit.Count; $i++) {
                $lbl = '?'; if ($i -lt $seatLabels.Count) { $lbl = $seatLabels[$i] }
                if ($withScale) { Emit ("| {0} | {1} | {2} | {3} |" -f $lbl, (Code $hit[$i].guid), (Pos $hit[$i]), $hit[$i].sx) }
                else            { Emit ("| {0} | {1} | {2} |" -f $lbl, (Code $hit[$i].guid), (Pos $hit[$i])) }
            }
        }
        'seatGrid' {
            # One row per image hash, one column per seat (each player has their own copy).
            if ($byHash) {
                $cells = @(); foreach ($lbl in $seatLabels) { $cells += $lbl }
                Emit ("| 项目 | hash | {0} |" -f ($cells -join ' | '))
                Emit ("|---|---|{0}" -f ('---|' * $cells.Count))
                foreach ($p in $byHash.PSObject.Properties) {
                    $grp = @(Sort-Rows @($hit | Where-Object { (H8 $_.url).ToUpperInvariant() -eq $p.Name.ToUpperInvariant() }) 'x')
                    $row = @()
                    for ($i = 0; $i -lt $seatLabels.Count; $i++) {
                        if ($i -lt $grp.Count) { $row += (Code $grp[$i].guid) } else { $row += '?' }
                    }
                    Emit ("| {0} | {1} | {2} |" -f $p.Value, (Code $p.Name), ($row -join ' | '))
                }
            }
        }
        'rows' {
            $hit = @(Sort-Rows $hit $sort)
            $h = @(); foreach ($c in $cols) { $h += (Get-Head $c) }
            Emit ("| {0} |" -f ($h -join ' | '))
            Emit ("|{0}" -f ('---|' * $h.Count))
            foreach ($r in $hit) {
                $cells = @()
                foreach ($c in $cols) {
                    switch ("$c") {
                        'guid'  { $cells += (Code $r.guid) }
                        'pos'   { $cells += (Pos $r) }
                        'x'     { $cells += ("{0:N2}" -f (Num $r.x)) }
                        'z'     { $cells += ("{0:N2}" -f (Num $r.z)) }
                        'y'     { $cells += ("{0:N2}" -f (Num $r.y)) }
                        'scale' { $cells += "$($r.sx)" }
                        'nick'  { $cells += "$($r.nick)" }
                        'name'  { $cells += "$($r.name)" }
                        default { $cells += "$($r.$c)" }
                    }
                }
                Emit ("| {0} |" -f ($cells -join ' | '))
            }
        }
        'deckByHash' {
            # Cards inside a Deck are NOT separate objects, so a deck is found by looking at its
            # children's image hashes.
            if ($byHash) {
                Emit ("| 项目 | deck guid | 位置 | 堆内张数 |")
                Emit ("|---|---|---|---|")
                foreach ($p in $byHash.PSObject.Properties) {
                    $found = $null
                    foreach ($d in @($rows | Where-Object { $_.name -eq 'Deck' -or $_.name -eq 'DeckCustom' })) {
                        $kids = @($rows | Where-Object { $_.parent -eq $d.guid })
                        if (@($kids | Where-Object { (H8 $_.url).ToUpperInvariant() -eq $p.Name.ToUpperInvariant() }).Count -gt 0) { $found = $d; break }
                    }
                    if ($found) {
                        Emit ("| {0} | {1} | {2} | {3} |" -f $p.Value, (Code $found.guid), (Pos $found), @($rows | Where-Object { $_.parent -eq $found.guid }).Count)
                    } else { Emit ("| {0} | ? | ? | ? |" -f $p.Value) }
                }
            }
        }
        'nearRef' {
            # Markers that sit ON a board: find the reference object (the LARGEST match, since a
            # board is the big one), keep the matches within `within` world units of it. Needed
            # because such markers cannot be told apart by name once they are on the board.
            $ref    = Prop $s 'ref'
            $within = Num (Prop $s 'within')
            if ($within -le 0) { $within = 28 }
            $refRows = @(Sort-Rows @($rows | Where-Object { Test-Match $_ $ref }) 'size')
            $board = $null; if ($refRows.Count -gt 0) { $board = $refRows[-1] }
            if ($board) {
                $onmap = @($hit | Where-Object {
                    [math]::Abs((Num $_.x) - (Num $board.x)) -lt $within -and [math]::Abs((Num $_.z) - (Num $board.z)) -lt $within })
                $onmap = @(Sort-Rows $onmap $sort)
                Emit ("| guid | x | y | z |")
                Emit ("|---|---|---|---|")
                foreach ($m in $onmap) { Emit ("| {0} | {1:N2} | {2:N2} | {3:N2} |" -f (Code $m.guid), (Num $m.x), (Num $m.y), (Num $m.z)) }
                $step = Prop $s 'stepPerUnit'
                if ($step -and $onmap.Count -gt 0 -and "$(Prop $s 'stepAxis')" -eq 'x') {
                    $formula = ("({0:N2} + {1}*N, {2:N2})" -f (Num $onmap[0].x), (Num $step), (Num $onmap[0].z))
                    Emit ("> ⇒ 第 N 格的位置 = {0}。" -f (Code $formula))
                }
            } else { Emit ("（没找到参照物：{0}）" -f "$(Prop $ref 'name')") }
        }
        default { if ($kind -ne '') { Emit ("（未知 kind: {0} —— schema 见 tts\docs\BOOTSTRAP.md）" -f $kind) } }
    }
    Emit ("")
    Note (Prop $s 'note')
    Emit ("")
}

[System.IO.File]::WriteAllText($Out, (($map -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
$bytes = (Get-Item $Out).Length
if ($Full) {
    Write-Host ("`nwrote {0}  ({1} lines, {2:N0} B)" -f $Out, $map.Count, $bytes)
} else {
    Write-Host ("`nfull map -> {0}  ({1} lines, {2:N0} B)" -f $Out, $map.Count, $bytes)
    Write-Host "  (stdout shows the seat table only; grep/read the file for the rest, or re-run with -Full)"
}
