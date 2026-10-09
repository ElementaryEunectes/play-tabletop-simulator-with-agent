# test_bridge_primitives.ps1 - the bridge's own commands must work, not just parse.
#
# WHY
#   validate_lua.js proves dsh_global.lua PARSES. It cannot see wrong routing, wrong argument
#   shapes, or a handler that returns nothing. On 2026-10-09 four such commands were added
#   (players / take / spawn / destroy) after two real mods showed they were the ones a trained
#   control layer kept missing, so they get a real behavioural check.
#
# WHAT IT DOES
#   1. gen_bridge_primitives_test.js extracts the changed block OUT OF THE REAL FILE (so the test
#      cannot drift from a copy) and wraps it in a stub TTS API;
#   2. run_lua.js runs that Lua under fengari, a Lua VM in JavaScript - there is no lua binary on
#      this machine and TTS ships none we can call;
#   3. the generated test asserts 16 cases, including the failures: a missing CardID, a ghost
#      container, an unknown action must all come back REPORTED, never as a silent dead handler.
#
# WHAT IT CANNOT PROVE
#   The stub's answers are the TTS API as documented, not as this TTS build behaves. Spawn and take
#   still need one live run after the save is re-baked (tts\docs\BOOTSTRAP.md section 2).
#   fengari is Lua 5.3 while TTS is 5.1, so 5.3-only syntax would pass here and fail in TTS.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_bridge_primitives.ps1
#   exit 0 = every case behaved, exit 1 = a case failed or the harness could not run
param(
    [string]$Root = '',
    [string]$OutFile = ''
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }

$lua     = Join-Path $Root 'tts\lua\dsh_global.lua'
$gen     = Join-Path $Root 'tts\tools\gen_bridge_primitives_test.js'
$runner  = Join-Path $Root 'tts\tools\run_lua.js'
$genLua  = Join-Path $Root 'tts\tests\gen_bridge_primitives.lua'
$logFile = if ($OutFile -ne '') { $OutFile } else { Join-Path $Root 'out\test_bridge_primitives.log' }
$outDir  = Split-Path -Parent $logFile
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# Output goes through a FILE: under the workspace-write confinement a piped grandchild loses its
# stdout silently (see MAINTENANCE.md section 0), and a gate that reads nothing would pass.
$lines = New-Object System.Collections.Generic.List[string]
function Add-Line([string]$s) { $lines.Add($s) | Out-Null }

foreach ($need in @($lua, $gen, $runner)) {
    if (-not (Test-Path -LiteralPath $need)) {
        Add-Line ("MISSING " + $need)
        [System.IO.File]::WriteAllLines($logFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("FAIL  missing input: " + $need)
        exit 1
    }
}

function Run-Node([string]$script, [string]$arg) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('bp_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    # The argument is optional, and an empty one must NOT be passed on: `node script "" > file` made
    # cmd.exe treat the empty string as its own /c command, so node never ran - a step that reported
    # success without doing anything. Same false-green family as an empty gate output.
    $argPart = if ($arg -ne '') { ' "{0}"' -f $arg } else { '' }
    $cmd = 'node "{0}"{1} > "{2}" 2>&1' -f $script, $argPart, $tmp
    # ⛔ Do NOT pre-set `$LASTEXITCODE = $null` here (2026-10-09): that assignment makes PowerShell
    # create an ordinary LOCAL variable of that name, which then SHADOWS the automatic one - and the
    # automatic variable is what cmd updates. The read afterwards returned EMPTY, which failed the
    # gate on a run that had passed with "28 passed, 0 failed". Measured in a function: pre-set ->
    # code=[], no pre-set -> code=[0]. Read it; never assign it.
    & cmd /c $cmd | Out-Null
    $code = $LASTEXITCODE
    $text = ''
    if (Test-Path -LiteralPath $tmp) { $text = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8); Remove-Item $tmp -Force }
    return @{ code = $code; text = $text }
}

# 1. generate the Lua test from the real file
$g = Run-Node $gen $lua
Add-Line '--- generator ---'
foreach ($l in ($g.text -split "`r?`n")) { if ($l -ne '') { Add-Line $l } }

# 2. run it under fengari
$r = Run-Node $runner $genLua
Add-Line '--- run ---'
foreach ($l in ($r.text -split "`r?`n")) { if ($l -ne '') { Add-Line $l } }

# 2b. the whole bridge must LOAD and every definition in it must be reachable. WHY (F8, 2026-10-09):
#     the block extracted above starts BELOW the splice that broke the file, so it walked straight
#     past 250 lines that had become the body of setCount() - every gate stayed green while four
#     commands were dead in the live game. Extraction proves what it extracted; this proves the
#     source it was extracted from actually loads and defines what it registers.
$vf = Join-Path $Root 'tts\tools\verify_f8.js'
Add-Line '--- bridge load check (every definition reachable) ---'
$vfStatus = Join-Path $Root 'cache\dsh_verify_f8_status.txt'
if (Test-Path -LiteralPath $vfStatus) { Remove-Item -LiteralPath $vfStatus -Force }
if (-not (Test-Path -LiteralPath $vf)) {
    Add-Line 'FAIL  missing tts\tools\verify_f8.js'
} else {
    # Judge on the file the child writes, not on an exit code that can be lost through cmd.exe.
    $v = Run-Node $vf $vfStatus
    foreach ($l in ($v.text -split "`r?`n")) { if ($l -ne '') { Add-Line $l } }
    $vfVerdict = ''
    if (Test-Path -LiteralPath $vfStatus) { $vfVerdict = ([System.IO.File]::ReadAllText($vfStatus, [System.Text.Encoding]::UTF8)).Trim() }
    if ($vfVerdict -eq 'VERDICT=PASS' -and $v.text -match 'MISSING=0') {
        Add-Line 'PASS  bridge definitions all reachable'
    } else {
        Add-Line ("FAIL  the bridge does not load, or a definition in it is unreachable (status='" + $vfVerdict + "')")
    }
}

# 3. the generated file must be reproducible: a committed artefact that disagrees with its source is
#    how a green gate hides a change nobody re-ran.
$snapshot = ''
if (Test-Path -LiteralPath $genLua) { $snapshot = [System.IO.File]::ReadAllText($genLua, [System.Text.Encoding]::UTF8) }
$g2 = Run-Node $gen $lua
$regen = ''
if (Test-Path -LiteralPath $genLua) { $regen = [System.IO.File]::ReadAllText($genLua, [System.Text.Encoding]::UTF8) }
if ($snapshot -ne '' -and $snapshot -ne $regen) {
    $lines.Add('FAIL  generated Lua test was stale (regenerated content differs)') | Out-Null
    [System.IO.File]::WriteAllLines($logFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'FAIL  generated Lua test was stale - it has been regenerated, re-run the gate'
    exit 1
}

[System.IO.File]::WriteAllLines($logFile, $lines, (New-Object System.Text.UTF8Encoding($false)))

$passed = @($lines | Where-Object { $_ -like 'PASS  *' }).Count
$failed = @($lines | Where-Object { $_ -like 'FAIL  *' }).Count
$marker = @($lines | Where-Object { $_ -like '*all bridge primitive cases passed*' }).Count -gt 0

Write-Host ("bridge primitives: {0} passed, {1} failed  (log: {2})" -f $passed, $failed, $logFile)
if ($failed -gt 0) { foreach ($l in @($lines | Where-Object { $_ -like 'FAIL  *' })) { Write-Host ('  ' + $l) } }

# Both halves of the repo's gate rule: exit code 0 AND the success marker in the output.
# The verdict inputs are printed whether it passes or fails: "0 failed" on its own once read as a
# pass while $marker was false, and a gate that cannot say WHY it failed costs a round every time.
Write-Host ("verdict inputs: exit gen={0} run={1} marker={2} failed={3}" -f $g.code, $r.code, $marker, $failed)
if ($g.code -ne 0 -or $r.code -ne 0 -or -not $marker -or $failed -gt 0) {
    Write-Host 'BRIDGE PRIMITIVES NOT RUN OR FAILED'
    exit 1
}
Write-Host 'bridge primitives OK'
exit 0
