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
    [string]$Root = '',
    # Write the same lines to this file too. WHY: under the workspace-write confinement a caller
    # cannot capture a grandchild's stdout through a pipe (the text is silently dropped while the
    # exit code stays 0), and routing it through cmd for a file redirect is the "hidden console"
    # shape that can die with 0xC0000142. So the child writes its own file and the caller reads it.
    [string]$OutFile = ''
)
function Say([string]$Text) {
    [Console]::WriteLine($Text)
    # Append immediately, never at the end: a failed gate exits before any final write would run.
    if ($OutFile -ne '') { [System.IO.File]::AppendAllText($OutFile, $Text + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false))) }
}
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$Root = (Resolve-Path -LiteralPath $Root).Path

# gate = script, and the phrase its own output must contain when it really passed
$gates = @(
    @{ name = 'check_ps1 (BOM + parser)'; script = 'tts\check_ps1.ps1';               marker = 'parse errors'; args = @('-Quiet') },
    @{ name = 'param backfill';           script = 'tts\tests\test_param_backfill.ps1'; marker = 'all param defaults of' },
    @{ name = 'diff chain';               script = 'tts\tests\test_diff_index.ps1';    marker = 'all cases passed' },
    @{ name = 'game data (files)';        script = 'tts\tests\test_game_data.ps1';    marker = 'all cases passed' },
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
    $tmp = Join-Path (Join-Path $Root 'cache') ('dsh_gate_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    # NO cmd.exe here: launching through cmd is the console-isolating shape that dies with
    # 0xC0000142 (Windows ACL backend, documented). Instead the CHILD redirects its own streams to
    # the file from inside its own process - that is in-process redirection, not a pipe back to us.
    # Clear the inherited exit code BEFORE the launch: a child that never starts leaves it untouched,
    # and a stale 0 from the previous gate is exactly how an "all green" was once printed for tests
    # that produced nothing. Empty here means "did not run", which must not read as success.
    $LASTEXITCODE = $null
    $inner = "& {{ & '{0}'{1} *> '{2}' }}" -f $path, (($g.args | ForEach-Object { " '" + $_ + "'" }) -join ''), $tmp
    & powershell -NoProfile -ExecutionPolicy Bypass -Command $inner
    $code = $LASTEXITCODE
    $text = ''
    if (Test-Path -LiteralPath $tmp) { $text = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8); Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    $ran  = ($text.Trim().Length -gt 0)          # a child that never started returns NOTHING
    $hit  = ($text -match [regex]::Escape($g.marker))
    if (-not $ran) { Write-Host ("NOT RUN  {0}  <- no output at all (child process did not start?)" -f $g.name); $failed++; continue }
    if ($code -eq 0 -and $hit) { Write-Host ("PASS     {0}" -f $g.name); continue }
    Say ("FAIL     {0}  exit={1} marker={2}" -f $g.name, $code, $hit)
    $out | Select-Object -Last 8 | ForEach-Object { Write-Host ("           " + $_) }
    $failed++
}
Say ''
if ($failed -gt 0) { Write-Host ("{0} gate(s) did not pass" -f $failed); exit 1 }
Say 'all gates passed (exit code AND success marker)'
