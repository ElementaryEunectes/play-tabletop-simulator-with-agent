# test_game_data.ps1 - offline gate: the toolkit's GAME DATA lives in files, and the code has none.
#
# WHY THIS EXISTS (2026-10-09)
#   card.ps1 shipped this toolkit's first campaign's card names inside a hashtable, and bootstrap.ps1
#   hard-coded that same campaign's image hashes, nicknames and legends. Both are game data, and the
#   toolkit is supposed to work "for any TTS mod": on any other mod those tables matched nothing -
#   or, worse, matched something wrong - while the script looked like it had answered.
#   This gate runs both tools against a FAKE game whose every recognition fact is in fixtures\, and
#   the decisive cases are the NEGATIVE ones: with the data file absent, the tool must NOT still
#   know the answer (that is what "the data is not in the code" means, and it is the only assertion
#   a leftover hardcoded table cannot pass).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_game_data.ps1
#   exit 0 = all cases passed, exit 1 = something regressed.
#
# IN-PROCESS, on purpose: no child PowerShell is spawned (the workspace-write confinement refuses
# that shape), so this gate runs under the confinement too. Both tools are terminal CLI tools that
# end their failure paths with `exit`; measured 2026-10-09: a script FILE's `exit` is caught at that
# file's own boundary, the caller keeps running, and $LASTEXITCODE carries the code.
$ErrorActionPreference = 'Stop'
$here     = $PSScriptRoot
$root     = Split-Path -Parent (Split-Path -Parent $here)
$card     = Join-Path $root 'tts\card.ps1'
$boot     = Join-Path $root 'tts\bootstrap.ps1'
$fx       = Join-Path $here 'fixtures'
$idx      = Join-Path $fx 'fake_obj_index.csv'
$objFull  = Join-Path $fx 'fake_objects.json'
$objMin   = Join-Path $fx 'fake_objects_min.json'
$cardsDb  = Join-Path $fx 'fake_cards.md'
$aliasDb  = Join-Path $fx 'fake_alias.json'
$tmp      = Join-Path ([System.IO.Path]::GetTempPath()) ('tts_gamedata_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$missing = Join-Path $tmp 'no_such_objects.json'
$badJson = Join-Path $tmp 'broken_objects.json'
Set-Content -LiteralPath $badJson -Encoding UTF8 -Value '{ "seats": { "name": "HandTrigger", '

$script:failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail) {
    if ($Ok) { Write-Host ("PASS  {0}" -f $Name) }
    else { $script:failed++; Write-Host ("FAIL  {0}   <- {1}" -f $Name, $Detail) -ForegroundColor Red }
}
# Call a tool IN-PROCESS and collect what it said. `6>&1` (not a pipe) is what captures Write-Host.
# $global:LASTEXITCODE, with the scope spelled out: a plain assignment to $LASTEXITCODE inside a
# FUNCTION creates a function-local copy, so the callee's exit code landed in the global one while
# this helper kept reading its own $null - every code assertion "passed" as 0. (The other half of
# the rule: clear it first, because a callee that does NOT exit leaves the previous value there,
# which is exactly how a runner once reported green for a script that never ran.)
function Invoke-Tool([string]$Path, [hashtable]$Params) {
    $global:LASTEXITCODE = $null
    $stream = @(& $Path @Params 6>&1)
    $code = 0
    if ($null -ne $global:LASTEXITCODE) { $code = $global:LASTEXITCODE }
    return [pscustomobject]@{ code = $code; text = ((@($stream) | ForEach-Object { "$_" }) -join [Environment]::NewLine) }
}
function Read-Text([string]$p) { if (Test-Path -LiteralPath $p) { return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) } return '' }

try {
    # case 1 - the alias table comes from cache\<game>_alias.json
    $r = Invoke-Tool $card @{ Q = 'fire'; CardsFile = $cardsDb; AliasFile = $aliasDb }
    Check 'card: an alias from the JSON resolves' ($r.code -eq 0 -and $r.text -match '火球术') ("code=$($r.code) :: $($r.text)")

    # case 2 - THE PIN: with no alias file, 'fire' must NOT resolve. A table left in the code would
    # still answer here, which is why this negative case is the point of the whole gate.
    $r = Invoke-Tool $card @{ Q = 'fire'; CardsFile = $cardsDb; AliasFile = $missing }
    Check 'card: with no alias file the English word does NOT resolve' ($r.code -eq 2 -and $r.text -match 'NOT FOUND') ("code=$($r.code) :: $($r.text)")
    Check 'card: and it says which alias file it wanted' ($r.text -match 'no_such_objects\.json') ("code=$($r.code) :: $($r.text)")

    # case 3 - plain text matching is unaffected by a missing alias file
    $r = Invoke-Tool $card @{ Q = '冰锥'; CardsFile = $cardsDb; AliasFile = $missing }
    Check 'card: plain text still resolves without an alias file' ($r.code -eq 0 -and $r.text -match '冰锥术') ("code=$($r.code) :: $($r.text)")

    # case 4 - no -Q: our own two-line usage, not PowerShell's mandatory-parameter dump
    $r = Invoke-Tool $card @{ Q = ''; CardsFile = $cardsDb }
    Check 'card: no -Q -> usage line, code 2' ($r.code -eq 2 -and $r.text -match 'usage:') ("code=$($r.code) :: $($r.text)")

    # case 5 - a missing objects.json is an ERROR NAMING ITSELF (not an empty map that reads like an
    # answer), and it points at the command that produces the raw material for writing one.
    $r = Invoke-Tool $boot @{ Index = $idx; Objects = $missing; Out = (Join-Path $tmp 'map5.md') }
    Check 'bootstrap: missing objects.json -> code 1' ($r.code -eq 1) ("code=$($r.code) :: $($r.text)")
    Check 'bootstrap: names the file it wanted' ($r.text -match 'no_such_objects\.json') $r.text
    Check 'bootstrap: points at -Inventory' ($r.text -match '-Inventory') $r.text
    Check 'bootstrap: and does not write a map' (-not (Test-Path -LiteralPath (Join-Path $tmp 'map5.md')))

    # case 6 - broken JSON is reported as broken, not as "nothing matched"
    $r = Invoke-Tool $boot @{ Index = $idx; Objects = $badJson; Out = (Join-Path $tmp 'map6.md') }
    Check 'bootstrap: invalid JSON -> code 1 and says so' ($r.code -eq 1 -and $r.text -match 'not valid JSON') ("code=$($r.code) :: $($r.text)")

    # case 7 - -Inventory needs NO objects.json: it is how you teach a mod nobody has taught yet
    $inv = Join-Path $tmp 'inv.md'
    $r = Invoke-Tool $boot @{ Index = $idx; Objects = $missing; Inventory = $true; InventoryOut = $inv }
    $invText = Read-Text $inv
    Check 'inventory: runs with no objects.json' ($r.code -eq 0 -and (Test-Path -LiteralPath $inv)) ("code=$($r.code) :: $($r.text)")
    Check 'inventory: name histogram' ($invText -match 'Custom_Tile\s+x8') ("custom_tile line missing")
    Check 'inventory: nick histogram' ($invText -match '金币\s+x4') 'nick line missing'
    Check 'inventory: image-hash histogram' ($invText -match 'AAAA1111\s+x4') 'hash line missing'

    # case 8 - the full map renders from objects.json: seats in x order, and the off-table stray
    # HandTrigger (z=+114) must NOT be pulled into the seat row (zBelow in the data file).
    $map8 = Join-Path $tmp 'map8.md'
    $r = Invoke-Tool $boot @{ Index = $idx; Objects = $objFull; Out = $map8; Full = $true }
    $m = Read-Text $map8
    Check 'bootstrap: full map -> code 0, file written' ($r.code -eq 0 -and (Test-Path -LiteralPath $map8)) ("code=$($r.code) :: $($r.text)")
    Check 'seats: P4..P1 in x order' `
        ($m -match [regex]::Escape('| **P4** | `a00001`') -and $m -match [regex]::Escape('| **P1** | `a00004`')) 'seat rows wrong'
    Check 'seats: the stray (off-table) zone is excluded' (-not ($m -match 'a00005')) 'a00005 leaked into the map'

    # case 9 - every label below comes from the JSON; the code has no idea what these objects are
    foreach ($want in @('矿石', '木材', '事件牌（2 张）', '玩家标记', '袋子A', '袋子B')) {
        Check ("sections: label from objects.json [{0}]" -f $want) ($m -match [regex]::Escape($want)) "missing: $want"
    }

    # case 10 - deckByHash: found through its CHILDREN's image hash (cards in a deck are not objects)
    Check 'deck: found by child image hash, with its child count' `
        ($m -match [regex]::Escape('| 事件牌（2 张） | `d00001`') -and $m -match '\|\s*2\s*\|') 'deck row wrong'

    # case 11 - nearRef: markers on the board, plus the data-declared per-point step
    Check 'nearRef: only markers within the board radius' ($m -match 'e00002' -and $m -match 'e00003') 'markers missing'
    Check 'nearRef: step line rendered from stepPerUnit' ($m -match [regex]::Escape('1.5*N')) 'step line missing'

    # case 12 - THE OTHER PIN: with a minimal objects.json (seats only) the game-specific sections
    # are gone. If any of those tables were still in the code, they would show up here.
    $map12 = Join-Path $tmp 'map12.md'
    $r = Invoke-Tool $boot @{ Index = $idx; Objects = $objMin; Out = $map12 }
    $m12 = Read-Text $map12
    Check 'minimal objects.json: seat table still renders' ($r.code -eq 0 -and $m12 -match [regex]::Escape('| **P4** | `a00001`')) ("code=$($r.code)")
    Check 'minimal objects.json: no section titles from the other file' (-not ($m12 -match '矿石' -or $m12 -match '袋子A' -or $m12 -match '金币')) 'a section leaked in from code, not from the file'

    # case 13 - columns are declared per section, and their headings are readable
    Check 'rows: declared columns and their headings' ($m -match [regex]::Escape('| guid | 昵称 | 位置 |')) 'heading row wrong'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:failed -gt 0) { Write-Host ("`n{0} case(s) FAILED" -f $script:failed); exit 1 }
Write-Host "`nall cases passed"
