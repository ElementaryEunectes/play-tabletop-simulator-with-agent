# test_diff_index.ps1 - offline self-test for diff_index.ps1.
#
# Needs NO Tabletop Simulator and NO save: fake_live_index.ps1 stands in for live_index.ps1
# and fixtures\*.csv are synthetic, so this runs anywhere, including on a fresh clone.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_diff_index.ps1
#   exit 0 = all cases passed, exit 1 = something regressed.
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
function Run-Diff([string[]]$Extra) {
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $diff) + $Extra
    $out = & powershell @argv 6>&1
    return [pscustomobject]@{ code = $LASTEXITCODE; text = ($out | Out-String) }
}
function Summary([string]$Text) {
    $m = [regex]::Match($Text, 'SUMMARY\s+(.*)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return '(no SUMMARY line)'
}

try {
    # case 1 - one of every change class: moved, flipped, reparented, state, removed, added
    $r = Run-Diff @('-Before', (Join-Path $fixtures 'before.csv'), '-After', (Join-Path $tmp 'live1.csv'), '-LiveIndex', $stub)
    Check 'diff: exit 0' ($r.code -eq 0) ("exit=$($r.code)")
    $want = 'added=1 removed=1 moved=1 flipped=1 reparented=1 state=1'
    Check 'diff: detects all six change classes' ($r.text -match [regex]::Escape($want)) (Summary $r.text)

    # case 2 - -Snapshot freezes the live snapshot into the baseline
    $base2 = Join-Path $tmp 'base2.csv'
    $r = Run-Diff @('-Snapshot', '-Before', $base2, '-After', (Join-Path $tmp 'live2.csv'), '-LiveIndex', $stub)
    Check 'snapshot: exit 0' ($r.code -eq 0) ("exit=$($r.code)")
    Check 'snapshot: wrote the baseline' (Test-Path -LiteralPath $base2) $base2

    # case 3 - a baseline compared against an identical snapshot must be silent
    $r = Run-Diff @('-Before', $base2, '-After', (Join-Path $tmp 'live3.csv'), '-LiveIndex', $stub)
    $zero = 'added=0 removed=0 moved=0 flipped=0 reparented=0 state=0'
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
    $r = Run-Diff @('-Before', (Join-Path $fixtures 'before.csv'), '-After', (Join-Path $tmp 'live4.csv'), '-LiveIndex', $blankStub)
    Check 'capability: no parent/gm/ss -> prints the warning naming them' ($r.text -match 'snapshot carries no parent/gm/ss values' -and $r.text -match 'reparented' -and $r.text -match 'state') (Summary $r.text)
    Check 'capability: that run reports reparented=0 state=0' ($r.text -match 'reparented=0' -and $r.text -match 'state=0') (Summary $r.text)

    # case 5 - positive control: when the snapshot DOES carry the columns, no NOTE
    $r = Run-Diff @('-Before', (Join-Path $fixtures 'before.csv'), '-After', (Join-Path $tmp 'live5.csv'), '-LiveIndex', $stub)
    Check 'capability: values present -> no warning' (-not ($r.text -match 'snapshot carries no parent/gm/ss values')) 'warning printed even though parent/gm/ss had values'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:failed -gt 0) { Write-Host ("`n{0} case(s) FAILED" -f $script:failed); exit 1 }
Write-Host "`nall cases passed"
