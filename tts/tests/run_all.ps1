# run_all.ps1 - run every offline gate and refuse to be fooled by an empty exit code.
#
# WHY THIS EXISTS (2026-10-09): while the workspace-write confinement was failing to launch child
# processes, `& powershell -File tts\tests\test_x.ps1` returned NOTHING and left $LASTEXITCODE empty
# - and an ad-hoc aggregation that only checked `$LASTEXITCODE -ne 0` printed "all green" for tests
# that never ran. That is the same false-green class this repository already has a pitfall about.
#
# THE RULE HERE: a gate counts as passed only when
#     it exited 0  AND  its output contains its own success marker.
# A gate that cannot even be launched is reported as NOT RUN, not as passed.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\run_all.ps1
#   exit 0 = every gate ran and reported success; exit 1 = at least one did not
param(
    [string]$Root = ''
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$Root = (Resolve-Path -LiteralPath $Root).Path

# gate = script, and the phrase its own output must contain when it really passed
$gates = @(
    @{ name = 'check_ps1 (BOM + parser)'; script = 'tts\check_ps1.ps1';               marker = 'parse errors'; args = @('-Quiet') },
    @{ name = 'param backfill';           script = 'tts\tests\test_param_backfill.ps1'; marker = 'all param defaults of' },
    @{ name = 'diff chain';               script = 'tts\tests\test_diff_index.ps1';    marker = 'all cases passed' },
    @{ name = 'instruction hygiene';      script = 'tts\tests\test_agents_hygiene.ps1'; marker = 'all checks passed' },
    @{ name = 'doc references';           script = 'tts\tests\test_doc_refs.ps1';      marker = 'all shipped path references resolve' }
)

$failed = 0
foreach ($g in $gates) {
    $path = Join-Path $Root $g.script
    if (-not (Test-Path -LiteralPath $path)) { Write-Host ("NOT RUN  {0}  <- missing {1}" -f $g.name, $g.script); $failed++; continue }
    # Launch through cmd with the output redirected to a FILE, then read that file. WHY (2026-10-09):
    # under the workspace-write confinement a grandchild's stdout is silently lost when it is
    # captured through a PowerShell pipe (`& powershell ... 2>&1` returns nothing while
    # $LASTEXITCODE stays 0), and a numbered file handle works. Reading a file also keeps the
    # positive-evidence rule honest: an empty file means NOT RUN, never "passed".
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh_gate_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    $cmdLine = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}"{1} > "{2}" 2>&1' -f $path, (($g.args | ForEach-Object { ' ' + $_ }) -join ''), $tmp
    & cmd /c $cmdLine
    $code = $LASTEXITCODE
    $text = ''
    if (Test-Path -LiteralPath $tmp) { $text = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8); Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    $ran  = ($text.Trim().Length -gt 0)          # a child that never started returns NOTHING
    $hit  = ($text -match [regex]::Escape($g.marker))
    if (-not $ran) { Write-Host ("NOT RUN  {0}  <- no output at all (child process did not start?)" -f $g.name); $failed++; continue }
    if ($code -eq 0 -and $hit) { Write-Host ("PASS     {0}" -f $g.name); continue }
    Write-Host ("FAIL     {0}  exit={1} marker={2}" -f $g.name, $code, $hit)
    $out | Select-Object -Last 8 | ForEach-Object { Write-Host ("           " + $_) }
    $failed++
}
Write-Host ''
if ($failed -gt 0) { Write-Host ("{0} gate(s) did not pass" -f $failed); exit 1 }
Write-Host 'all gates passed (exit code AND success marker)'
