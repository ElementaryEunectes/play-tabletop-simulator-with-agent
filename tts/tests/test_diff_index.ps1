# test_diff_index.ps1 - offline self-test for diff_index.ps1.
#
# Needs NO Tabletop Simulator and NO save: fake_live_index.ps1 stands in for live_index.ps1
# and fixtures\*.csv are synthetic, so this runs anywhere, including on a fresh clone.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_diff_index.ps1
#   exit 0 = all cases passed, exit 1 = something regressed.
#
# NO CHILD PROCESS (2026-10-09): diff_index.ps1 is called IN-PROCESS from here, so this gate runs
# under the workspace-write confinement too. See Run-Diff's comment for why the old spawn was both
# refused by the sandbox and unnecessary.
#
# SCOPE (2026-10-09): this covers the LOGIC of all six change classes. The `after` fixture
# deliberately supplies parent/gm/ss values, which the REAL live index does not (live_index.ps1
# hard-codes them empty) - so on a real table only four classes can fire. Cases 4 and 5 pin that
# down: without those columns diff_index.ps1 must print a NOTE, and with them it must not.
#
# Why this exists: diff_index.ps1 was dead for a whole session because its param() defaults'
# were never backfilled (the script parsed fine and then died on an empty path). A syntax
# check cannot see that. This is the positive control for the diff chain.
$ErrorActionPreference = 'Stop'
$here     = $PSScriptRoot
$root     = Split-Path -Parent (Split-Path -Parent $here)
$diff     = Join-Path $root 'tts\diff_index.ps1'
$fixtures = Join-Path $here 'fixtures'
$stub     = Join-Path $here 'fake_live_index.ps1'
$tmp      = Join-Path ([System.IO.Path]::GetTempPath()) ('tts_diff_test_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$script:failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail) {
    if ($Ok) { Write-Host ("PASS  {0}" -f $Name) }
    else { $script:failed++; Write-Host ("FAIL  {0}   <- {1}" -f $Name, $Detail) -ForegroundColor Red }
}
function Run-Diff([string]$Before, [string]$After, [string]$LiveIndex, [switch]$Snapshot) {
    # IN-PROCESS, on purpose (2026-10-09, D0). This used to spawn `cmd /c powershell -File ...` and
    # read a redirected file, because under the workspace-write confinement a grandchild's stdout is
    # silently dropped (the text comes back empty while the exit code stays 0). But a nested
    # PowerShell is exactly the shape that confinement refuses - it constrains a command AND its
    # descendants, and "hidden PowerShell" is malware behaviour - so this gate only ever ran with the
    # confinement lifted. The spawn was never necessary: diff_index.ps1 uses `return`, not a
    # top-level `exit`, so it can run in THIS process.
    # `6>&1` -- NOT `|` -- captures its output: it prints with Write-Host, i.e. the INFORMATION
    # stream, which a pipe never sees. A failure path's `return 1` arrives as a trailing int on the
    # success stream, so peel that off to get the code.
    # The arguments are re-splatted as a HASHTABLE. An array would splat POSITIONALLY, so
    # '-Before <path>' would be handed to diff_index.ps1's $Before as the literal "-Before"
    # (that is exactly how the first in-process version of this test broke).
    $p = @{}
    if ($Before)    { $p['Before']    = $Before }
    if ($After)     { $p['After']     = $After }
    if ($LiveIndex) { $p['LiveIndex'] = $LiveIndex }
    if ($Snapshot)  { $p['Snapshot']  = $true }
    $stream = @(& $diff @p 6>&1)
    $code = 0
    if ($stream.Count -gt 0 -and $stream[-1] -is [int]) {
        $code = $stream[-1]
        if ($stream.Count -gt 1) { $stream = @($stream[0..($stream.Count - 2)]) } else { $stream = @() }
    }
    $text = (@($stream) | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    return [pscustomobject]@{ code = $code; text = $text }
}
function Summary([string]$Text) {
    $m = [regex]::Match($Text, 'SUMMARY\s+(.*)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return '(no SUMMARY line)'
}

try {
    # case 1 - one of every change class: moved, flipped, reparented, state, removed, added
    $r = Run-Diff -Before (Join-Path $fixtures 'before.csv') -After (Join-Path $tmp 'live1.csv') -LiveIndex $stub
    Check 'diff: returns 0 (happy path takes no error branch)' ($r.code -eq 0) ("code=$($r.code)")
    Check 'diff: no ERR line on the happy path' (-not ($r.text -match '(?m)^ERR ')) (Summary $r.text)
    $want = 'added=1 removed=1 moved=1 flipped=1 reparented=1 state=1 nick=0'
    Check 'diff: detects all six change classes' ($r.text -match [regex]::Escape($want)) (Summary $r.text)

    # case 2 - -Snapshot freezes the live snapshot into the baseline
    $base2 = Join-Path $tmp 'base2.csv'
    $r = Run-Diff -Snapshot -Before $base2 -After (Join-Path $tmp 'live2.csv') -LiveIndex $stub
    Check 'snapshot: returns 0' ($r.code -eq 0) ("code=$($r.code)")
    Check 'snapshot: says what it froze' ($r.text -match 'SNAPSHOT') (Summary $r.text)
    Check 'snapshot: wrote the baseline' (Test-Path -LiteralPath $base2) $base2

    # case 3 - a baseline compared against an identical snapshot must be silent
    $r = Run-Diff -Before $base2 -After (Join-Path $tmp 'live3.csv') -LiveIndex $stub
    $zero = 'added=0 removed=0 moved=0 flipped=0 reparented=0 state=0 nick=0'
    Check 'diff: identical snapshots are quiet' ($r.text -match [regex]::Escape($zero)) (Summary $r.text)

    # case 4 - a snapshot carrying no parent/gm/ss values (exactly what live_index.ps1 produces)
    # must SAY that those two classes are not reported. Built here rather than tracked, so the
    # fixture set stays small.
    $blankStub = Join-Path $tmp 'blank_stub.ps1'
    $blankCsv  = Join-Path $tmp 'blank_after.csv'
    $rows = @(Import-Csv -LiteralPath (Join-Path $fixtures 'after.csv'))
    foreach ($row in $rows) { $row.parent = ''; $row.gm = ''; $row.ss = '' }
    $rows | Export-Csv -LiteralPath $blankCsv -NoTypeInformation -Encoding UTF8
    Set-Content -LiteralPath $blankStub -Encoding UTF8 -Value @(
        "param([string]`$Out = '', [int]`$Limit = 1200)",
        ("Copy-Item -LiteralPath '{0}' -Destination `$Out -Force" -f $blankCsv)
    )
    $r = Run-Diff -Before (Join-Path $fixtures 'before.csv') -After (Join-Path $tmp 'live4.csv') -LiveIndex $blankStub
    Check 'capability: no parent/gm/ss -> prints the warning naming them' ($r.text -match 'snapshot carries no parent/gm/ss values' -and $r.text -match 'reparented' -and $r.text -match 'state') (Summary $r.text)
    Check 'capability: that run reports reparented=0 state=0' ($r.text -match 'reparented=0' -and $r.text -match 'state=0') (Summary $r.text)

    # case 5 - positive control: when the snapshot DOES carry the columns, no NOTE
    $r = Run-Diff -Before (Join-Path $fixtures 'before.csv') -After (Join-Path $tmp 'live5.csv') -LiveIndex $stub
    Check 'capability: values present -> no warning' (-not ($r.text -match 'snapshot carries no parent/gm/ss values')) 'warning printed even though parent/gm/ss had values'

    # case 6 - NICKNAME is a first-class signal: the turn token writes "DSH-TURN <n>" into it, and
    # that channel needs no help from the mod's own turn machine.
    $nickStub = Join-Path $tmp 'nick_stub.ps1'
    $nickCsv  = Join-Path $tmp 'nick_after.csv'
    $nrows = @(Import-Csv -LiteralPath (Join-Path $fixtures 'after.csv'))
    foreach ($row in $nrows) { if ($row.guid -eq 'g0005') { $row.nick = 'DSH-TURN 1' } }
    $nrows | Export-Csv -LiteralPath $nickCsv -NoTypeInformation -Encoding UTF8
    Set-Content -LiteralPath $nickStub -Encoding UTF8 -Value @(
        "param([string]`$Out = '', [int]`$Limit = 1200)",
        ("Copy-Item -LiteralPath '{0}' -Destination `$Out -Force" -f $nickCsv)
    )
    $r = Run-Diff -Before (Join-Path $fixtures 'before.csv') -After (Join-Path $tmp 'live6.csv') -LiveIndex $nickStub
    Check 'nick: a nickname change is reported as nick=1' ($r.text -match 'nick=1') (Summary $r.text)
    Check 'nick: the section shows the transition' ($r.text -match 'NICK' -and $r.text -match 'DSH-TURN 1') (Summary $r.text)

    # case 7 - an in-process call that hits an error path must report its code to THIS caller.
    # What it pins: with `return 1` the code arrives as a value on the success stream; the previous
    # `exit 1` was measured to leave $code at 0 here (the caller keeps running either way, and only
    # inherits $LASTEXITCODE) - so this check genuinely discriminates the two forms.
    $r = Run-Diff -Before (Join-Path $tmp 'no_such_baseline.csv') -After (Join-Path $tmp 'live7.csv') -LiveIndex $stub
    Check 'in-process: the error path returns code 1 to the caller' ($r.code -eq 1) ("code=$($r.code)")
    Check 'in-process: the error path names the missing file' ($r.text -match 'ERR missing') (Summary $r.text)

    # case 8 - pin the contract itself, so a later edit cannot quietly put an `exit` back into a
    # script that this chain calls in-process. Tokens, not a line regex: the exits this replaced sat
    # INLINE on one-liners (`{ ...; exit 1 }`), and a line-anchored regex sailed straight past them
    # (control run: an inline `exit 1` put back into diff_index.ps1 left this check green).
    # The tokenizer also cannot be fooled by the comments above that discuss the word.
    $inProcess = @('tts\diff_index.ps1', 'tts\live_index.ps1', 'tts\ds.ps1', 'tts\tests\fake_live_index.ps1')
    foreach ($rel in $inProcess) {
        $p = Join-Path $root $rel
        $tokens = $null; $parseErrs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$parseErrs)
        $exits = @($tokens | Where-Object { $_.Kind -eq 'Exit' })
        $where = ($exits | ForEach-Object { $_.Extent.StartLineNumber }) -join ','
        Check ("in-process safe: {0} contains no exit statement" -f $rel) ($exits.Count -eq 0) ("exit on line(s) $where")
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:failed -gt 0) { Write-Host ("`n{0} case(s) FAILED" -f $script:failed); exit 1 }
Write-Host "`nall cases passed"
