# start-agent.ps1 - launch DSH with THIS folder as the project workspace.
#
# WHY THIS STILL EXISTS
#   1. SESSION CWD. The project chain is injected only while the working directory is inside this
#      repo - the harness walks project-root -> cwd looking for AGENTS.md. Start dsh from anywhere
#      else and the project charter is simply NOT injected. Hence the Set-Location below.
#   2. WHICH HARNESS HOME. $DSH_HOME decides where the harness keeps its state AND which file fills
#      the "user global" instruction slot (<DSH_HOME>\AGENTS.md, name hard-coded, no opt-out switch).
#      This launcher points it at a per-project PROFILE (see tts\dsh_profile.ps1): a home whose
#      entries are links back to the shared ~\.dsh, and which deliberately carries NO instruction
#      file. Result: the global slot injects nothing, this project's own chain injects normally, and
#      no session history or credential is copied or migrated.
#
#   Two escape hatches, for the record:
#     -RepoAsHome   pin DSH_HOME to this repo. Dedupes the global slot (saves ~2.9 KB/request) but
#                   drags the harness home - sessions, credentials - into the working tree, and means
#                   migrating the state of a machine that already has some.
#     -PlainHome    leave $DSH_HOME exactly as the environment had it (then whatever <that>\AGENTS.md
#                   says IS injected on top of this project).
#
#   OBSOLETE REASON (it was the headline before 2026-10-08): "a stale $DSH_HOME makes every script
#      silently read/write a folder that no longer exists". tts\config.ps1 now checks whether
#      $DSH_HOME really contains tts\config.ps1 and otherwise falls back to its OWN location, so the
#      scripts heal themselves. Proven by a whole session running against ~\.dsh.
#
# USAGE (from anywhere):
#   powershell -NoProfile -ExecutionPolicy Bypass -File <project>\start-agent.ps1
#   ...then run `dsh web` (or plain `dsh`) in that same window.  Ordinary users: double-click start.cmd
#
# NOTE: param() must stay the first statement; nothing may precede it.
param(
    [switch]$NoLaunch,
    [string]$DshCommand = 'dsh web',
    [string]$Profile = '',            # '' = this repository's folder name
    [string]$Shared = '',             # '' = <user profile>\.dsh   (the home holding the real state)
    [switch]$RepoAsHome,
    [switch]$PlainHome
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $root

if ($RepoAsHome) {
    $env:DSH_HOME = $root
    Write-Host ("DSH_HOME = {0}   (repo-as-home: global slot deduped, harness state now lives in the repo)" -f $env:DSH_HOME)
} elseif ($PlainHome) {
    Write-Host ("DSH_HOME = {0}   (untouched: whatever the environment had)" -f $env:DSH_HOME)
} else {
    $dshHome = ''
    try {
        & (Join-Path $root 'tts\dsh_profile.ps1') -Name $Profile -Shared $Shared -Apply -Quiet | Out-Null
        $leaf = if ($Profile -ne '') { $Profile } else { Split-Path -Leaf $root }
        $base = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'dsh-profiles' }
                else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh-profiles' }
        $dshHome = Join-Path $base $leaf
        if (-not (Test-Path -LiteralPath (Join-Path $dshHome 'sessions'))) { throw 'profile is missing sessions\, refusing to use it' }
    } catch {
        $dshHome = if ($Shared -ne '') { $Shared } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh' }
        Write-Host ("WARN profile unavailable ({0}) -> falling back to {1}" -f $_.Exception.Message, $dshHome) -ForegroundColor Yellow
    }
    $env:DSH_HOME = $dshHome
    $global = Join-Path $dshHome 'AGENTS.md'
    Write-Host ("DSH_HOME = {0}" -f $env:DSH_HOME)
    Write-Host ("           global slot: {0}" -f $(if (Test-Path -LiteralPath $global) { 'PRESENT - it WILL be injected' } else { 'empty - nothing is injected from it' }))
}

Write-Host ("project  = {0}" -f $root)
if (-not (Test-Path (Join-Path $root 'tts\config.ps1'))) {
    Write-Host 'WARN: tts\config.ps1 not found under this project root.' -ForegroundColor Yellow
}
if ($NoLaunch) { Write-Host '(-NoLaunch: set the variable only; nothing started)'; return }
Write-Host ("launching: " + $DshCommand)
& powershell -NoProfile -Command $DshCommand
