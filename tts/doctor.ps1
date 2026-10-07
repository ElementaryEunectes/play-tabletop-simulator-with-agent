# doctor.ps1 - "is THIS machine ready, and what will it cost in context?"
#
# WHY
#   The repository has to work on a machine it has never seen. Almost every failure this
#   project has paid for was an ENVIRONMENT fact, not a code fact: a stale $DSH_HOME, a
#   TTS folder in a different place, a wrong PowerShell, a harness-home AGENTS.md that
#   doubles the per-request context for no reason. So: ask the machine.
#
# STRICTLY READ-ONLY. It starts nothing, writes nothing, touches no game state. It reads
# paths, counts bytes and opens one TCP connection.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\doctor.ps1
#
# ASCII output on purpose: this file is meant to be run on somebody else's computer.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'config.ps1')

$script:problems = @()
function Line([string]$label, [string]$value) { Write-Host ("  {0,-30} {1}" -f $label, $value) }
function Problem([string]$what, [string]$fix) { $script:problems += ("{0}  ->  {1}" -f $what, $fix); Write-Host ("  PROBLEM  {0}" -f $what) -ForegroundColor Red }
function OK([string]$label, [string]$value) { Line $label $value }

Write-Host "== 1. PowerShell =="
OK 'version' $PSVersionTable.PSVersion.ToString()
OK 'edition' ([string]$PSVersionTable.PSEdition)
if ($PSVersionTable.PSVersion.Major -lt 5) { Problem 'PowerShell is older than 5.1' 'the scripts use System.Drawing / WinRT / GDI' }

Write-Host "== 2. paths (tts\config.ps1 is the only resolver) =="
OK 'workspace root' $WorkspaceRoot
OK 'this file lives in' $PSScriptRoot
OK 'DSH_HOME (environment)' $(if ($env:DSH_HOME) { $env:DSH_HOME } else { '(unset)' })
$dshHome = [string]$env:DSH_HOME
if ($dshHome -ne '') {
    $dshHoldsProject = (Test-Path (Join-Path $dshHome 'tts\config.ps1'))
    OK 'DSH_HOME holds this project' ([string]$dshHoldsProject)
    if (-not $dshHoldsProject) {
        OK 'resolution used' 'this file own location (config.ps1 step 2)'
        Write-Host "           note: DSH_HOME points somewhere that is NOT this project; the scripts still" -ForegroundColor DarkGray
        Write-Host "                 work because config.ps1 self-heals, but the harness will treat that" -ForegroundColor DarkGray
        Write-Host "                 other folder as its home (sessions, credentials, profiles)." -ForegroundColor DarkGray
    }
}
foreach ($d in @(
    @{ n = 'TTS saves dir';  p = $TtsSavesDir;  need = $true  },
    @{ n = 'TTS images dir'; p = $TtsImagesDir; need = $false },
    @{ n = 'cache dir';      p = $DshCache;     need = $true  },
    @{ n = 'logs dir';       p = $DshLogs;      need = $false }
)) {
    $exists = Test-Path $d.p
    Line $d.n ("{0}   [{1}]" -f $d.p, $(if ($exists) { 'ok' } else { 'MISSING' }))
    if ($d.need -and -not $exists) { Problem ("{0} not found" -f $d.n) "set `$env:TTS_SAVES_DIR, or install Tabletop Simulator" }
}

Write-Host "== 3. context cost: what gets injected on EVERY request =="
# The harness injects $DSH_HOME\AGENTS.md (the user-global file) plus the project chain
# (AGENTS.md / CLAUDE.md from the repo root down to the working directory), deduplicated by
# path and content. So if DSH_HOME IS the repo root, one file fills both slots and you pay
# for it once. Anything else means the global file is paid for on top.
$projectAgents = Join-Path $WorkspaceRoot 'AGENTS.md'
$pSize = 0
if (Test-Path $projectAgents) { $pSize = (Get-Item $projectAgents).Length }
OK 'project AGENTS.md' ("{0} bytes" -f $pSize)
$total = $pSize
if ($dshHome -ne '' -and (Test-Path (Join-Path $dshHome 'AGENTS.md'))) {
    $gPath = Join-Path $dshHome 'AGENTS.md'
    $gSize = (Get-Item $gPath).Length
    if ($dshHome.TrimEnd('\') -eq $WorkspaceRoot.TrimEnd('\')) {
        OK 'harness-home AGENTS.md' ("{0} bytes  = same file as the project one (deduplicated)" -f $gSize)
    } else {
        OK 'harness-home AGENTS.md' ("{0} bytes  ({1})" -f $gSize, $gPath)
        $total += $gSize
        Write-Host "           note: this file is NOT part of the repository. Keep it to a few generic" -ForegroundColor DarkGray
        Write-Host "                 lines, or point DSH_HOME at the repo so it fills both slots." -ForegroundColor DarkGray
    }
}
foreach ($ov in @('AGENTS.local.md', 'CLAUDE.local.md')) {
    $op = Join-Path $WorkspaceRoot $ov
    if (Test-Path $op) { $n = (Get-Item $op).Length; $total += $n; OK ("overlay " + $ov) ("{0} bytes (adds on top, not deduplicated)" -f $n) }
}
OK 'INJECTED PER REQUEST (approx)' ("{0} bytes" -f $total)

Write-Host "== 4. Tabletop Simulator bridge =="
# netstat, NOT Get-NetTCPConnection: that cmdlet reports nothing for a port that is plainly
# listening in this sandbox (HANDOFF 6.12).
$port = 39999
$tcp = New-Object System.Net.Sockets.TcpClient
$listening = $false
try { $tcp.Connect('127.0.0.1', $port); $listening = $true } catch { }
$tcp.Close()
OK ("port {0}" -f $port) $(if ($listening) { 'LISTENING (TTS external editor API)' } else { 'nothing there - TTS is closed, or the save is not loaded' })
if ($listening) {
    Write-Host "           next: tts\play.ps1 turn      (board + dice + abilities + notebook, read-only)" -ForegroundColor DarkGray
} else {
    Write-Host "           next: start Tabletop Simulator and load the save; the bridge lives INSIDE the save." -ForegroundColor DarkGray
}

Write-Host "== 5. node (only needed to validate the Lua) =="
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) { OK 'node' ("{0}  ({1})" -f $node.Source, (& node --version)) }
else { Line 'node' 'not found - tts\validate_lua.js will not run (everything else works without it)' }

Write-Host "== 6. self-checks you can run next =="
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1"
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_diff_index.ps1"
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_param_backfill.ps1"

Write-Host ""
if ($script:problems.Count -gt 0) {
    Write-Host ("VERDICT: {0} problem(s) - see above." -f $script:problems.Count) -ForegroundColor Red
    exit 1
}
Write-Host "VERDICT: ready." -ForegroundColor Green
