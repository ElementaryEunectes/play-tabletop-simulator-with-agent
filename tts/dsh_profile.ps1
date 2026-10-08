# dsh_profile.ps1 - give ONE project its own DSH_HOME without moving the harness's state.
#
# WHY THIS EXISTS
#   DSH injects <DSH_HOME>\AGENTS.md (the "user global" file, name hard-coded) on top of the project
#   chain, and there is NO switch to exclude it. The two workarounds both hurt:
#     * pinning DSH_HOME to the repo (the old advice) drags the harness home - sessions, credentials,
#       profiles - into the working tree, and moves state for anyone who already has some;
#     * deleting the global file removes the cross-project charter for EVERY project.
#   A profile is the third way: a small home whose entries are junctions / hard links back to the
#   real <shared>\..., and which deliberately does NOT contain the instruction files. The global slot
#   then contributes NOTHING, this project's own chain still injects normally, and no state is copied
#   or migrated - the same sessions and credentials, reached through links.
#
# WHAT IT LINKS
#   Everything found in the shared home, so nothing breaks - EXCEPT the instruction files
#   (AGENTS.md / CLAUDE.md / AGENTS.local.md / CLAUDE.local.md), which are deliberately skipped.
#     directories -> junctions   (New-Item -ItemType Junction, no admin needed)
#     files       -> hard links  (New-Item -ItemType HardLink, same volume, no admin needed)
#
# USAGE
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\dsh_profile.ps1            # plan only
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\dsh_profile.ps1 -Apply      # create/repair
#   ... -Name <profile>            # default: this repository's folder name
#   ... -Shared <path>             # default: <user profile>\.dsh
#
# NOTE: param() must stay the first statement; nothing may precede it.
param(
    [string]$Name = '',
    [string]$Shared = '',
    [switch]$Apply,
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ($Name -eq '') { $Name = Split-Path -Leaf $repoRoot }
if ($Shared -eq '') { $Shared = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh' }

# %LOCALAPPDATA% is the Windows-correct place for per-user application data. Off Windows, fall back
# to a dot-directory in the home folder (XDG users can override with -ProfileRoot... not needed yet).
$base = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'dsh-profiles' }
        else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh-profiles' }
$profile = Join-Path $base $Name

# Instruction files are the WHOLE POINT: a profile must not carry one, otherwise the global slot
# would inject it again and nothing would have been gained.
$skip = @('AGENTS.md', 'CLAUDE.md', 'AGENTS.local.md', 'CLAUDE.local.md')

if (-not (Test-Path -LiteralPath $Shared)) { throw "shared harness home not found: $Shared" }

if (-not $Quiet) {
    Write-Host ("repo    : {0}" -f $repoRoot)
    Write-Host ("shared  : {0}" -f $Shared)
    Write-Host ("profile : {0}" -f $profile)
    Write-Host ("mode    : {0}" -f $(if ($Apply) { 'APPLY (creating/repairing)' } else { 'PLAN ONLY (read-only; add -Apply)' }))
    Write-Host ''
}

$planned = 0; $skipped = @(); $errors = @()
foreach ($item in @(Get-ChildItem -LiteralPath $Shared -Force)) {
    if ($skip -contains $item.Name) { $skipped += $item.Name; continue }
    $target = Join-Path $profile $item.Name
    $kind = if ($item.PSIsContainer) { 'junction' } else { 'hardlink' }
    $planned++

    if (Test-Path -LiteralPath $target) {
        if (-not $Quiet) { Write-Host ("  exists   [{0,-8}] {1}" -f $kind, $item.Name) }
        continue
    }
    if (-not $Quiet) { Write-Host ("  {0,-8} [{1,-8}] {2}" -f $(if ($Apply) { 'link' } else { 'would' }), $kind, $item.Name) }
    if (-not $Apply) { continue }
    try {
        if (-not (Test-Path -LiteralPath $profile)) { [void](New-Item -ItemType Directory -Path $profile -Force) }
        if ($item.PSIsContainer) { [void](New-Item -ItemType Junction -Path $target -Target $item.FullName -ErrorAction Stop) }
        else { [void](New-Item -ItemType HardLink -Path $target -Target $item.FullName -ErrorAction Stop) }
    } catch {
        $errors += ("{0}: {1}" -f $item.Name, $_.Exception.Message)
    }
}

Write-Host ''
Write-Host ("entries: {0} to link, {1} skipped on purpose{2}" -f $planned, $skipped.Count, $(if ($skipped.Count) { ' -> ' + ($skipped -join ', ') } else { '' }))
if ($skipped.Count -eq 0) {
    Write-Host 'WARN  the shared home has no AGENTS.md, so a profile buys nothing right now.' -ForegroundColor Yellow
}
if ($errors.Count -gt 0) {
    # throw, NOT exit: this script is meant to be called in-process (& ...) by start-agent.ps1, and
    # `exit` there would kill the caller's whole session. Standalone, an uncaught throw still exits 1.
    throw ("dsh_profile: {0}" -f ($errors -join ' | '))
}
if ($Apply) {
    Write-Host ''
    Write-Host 'use it with:'
    Write-Host ("  `$env:DSH_HOME = '{0}'" -f $profile)
    Write-Host '  start.cmd / start-agent.ps1 does this for you.'
    Write-Host ''
    Write-Host 'verify (should show the global slot as ABSENT, i.e. not injected):'
    Write-Host '  tts\doctor.ps1'
}
