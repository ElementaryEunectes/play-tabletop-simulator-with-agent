# start-agent.ps1 - launch DSH with THIS folder as the project workspace.
#
# WHY THIS STILL EXISTS
#   1. SESSION CWD. The project chain is injected only while the working directory is inside this
#      repo - the harness walks project-root -> cwd looking for AGENTS.md. Start dsh from anywhere
#      else and the project charter is simply NOT injected. Hence the Set-Location below.
#   2. WHICH HARNESS HOME. $DSH_HOME decides where the harness keeps its state AND which file fills
#      the "user global" instruction slot (<DSH_HOME>\AGENTS.md, name hard-coded, no opt-out switch).
#      This launcher points it at a per-project PROFILE (see <harness home>\platform\dsh_profile.ps1): a home whose
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
    [switch]$Profile,                 # OPT-IN: build/use a per-project profile home (junction farm).
                                      # NOT the default: on this machine the ACL-based Windows sandbox
                                      # fails to start child processes through it (0xc0000142).
    [string]$ProfileName = '',        # profile folder name; '' = this repository's folder name
    [string]$Shared = '',             # '' = <user profile>\.dsh   (the home holding the real state)
    [string]$DshProfile = '',         # ⭐ WHICH PROFILE THIS PROJECT BOOTS WITH - override on the command
                                      #    line; the project's own default is the single line
                                      #    $ProjectDshProfile below. '' = harness default (`web`).
                                      #    Mechanism + how to create/install a profile:
                                      #    tts\docs\INJECTION.md, section "A'".
    [switch]$RepoAsHome,
    [switch]$PlainHome                # explicit no-op form of the default
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $root

# ---- WHICH PROFILE: the one line that decides it (2026-10-09) -------------------------------
# ⭐ CHANGE THIS LINE to boot this project with its own profile; '' = the harness default (`web`).
#    A profile only changes what THAT profile composes: this project's profile empties the
#    "user global" instruction slot for itself, while every other project keeps the global
#    charter. That is the ONLY way to suppress it per project - there is no "ignore the global
#    file" switch (see tts\docs\INJECTION.md section 2 and section 4, plan A').
#    Creating/installing one is two commands; the launcher checks both and tells you.
$ProjectDshProfile = ''
if ($DshProfile -eq '') { $DshProfile = $ProjectDshProfile }
# An explicit -DshCommand still wins; otherwise the profile name builds the command.
if ($DshProfile -ne '' -and -not $PSBoundParameters.ContainsKey('DshCommand')) {
    $DshCommand = ("dsh --profile {0}" -f $DshProfile)
}

if ($RepoAsHome) {
    $env:DSH_HOME = $root
    Write-Host ("DSH_HOME = {0}   (repo-as-home: global slot deduped, harness state now lives in the repo)" -f $env:DSH_HOME)
} elseif (-not $Profile) {
    Write-Host ("DSH_HOME = {0}   (untouched: the harness home as the environment had it)" -f $env:DSH_HOME)
    Write-Host '                        its AGENTS.md IS injected; to empty that slot for THIS project,'
    Write-Host '                        set $ProjectDshProfile above (tts\docs\INJECTION.md, section 4 plan A'')'
} else {
    $dshHome = ''
    try {
        # The profile tool is platform layer: it lives in the harness home, NOT in this repository
        # (it moved out on 2026-10-09). A clone without it simply gets the fallback below.
        $profileScript = ''
        foreach ($cand in @(
            $(if ($env:DSH_HOME) { Join-Path $env:DSH_HOME 'platform\dsh_profile.ps1' }),
            (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh\platform\dsh_profile.ps1')
        )) { if ($cand -and (Test-Path -LiteralPath $cand)) { $profileScript = $cand; break } }
        if ($profileScript -eq '') { throw 'platform\dsh_profile.ps1 not found under the harness home' }
        & $profileScript -Name $Profile -Shared $Shared -Apply -Quiet | Out-Null
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

# ---- the profile must exist AND be installed, or the boot silently loses bundles -------------
if ($DshProfile -ne '') {
    # NOT $home: PowerShell variable names are case-insensitive and $HOME is read-only.
    $profilesHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh' }
    $pdir = Join-Path $profilesHome ("profiles\{0}" -f $DshProfile)
    Write-Host ("profile  = {0}   ({1})" -f $DshProfile, $pdir)
    if (-not (Test-Path -LiteralPath $pdir)) {
        Write-Host ("WARN profile folder does not exist - create it: dsh {0} --from-default-profile web" -f $DshProfile) -ForegroundColor Yellow
    } elseif (-not (Test-Path -LiteralPath (Join-Path $pdir 'node_modules'))) {
        # Verified 2026-10-09: without this, `dsh --profile <name> --dump-config` exits 1 with
        # "cannot resolve profile bundle ..." - the boot loses plugins instead of failing loudly.
        Write-Host ("WARN profile has no node_modules - install it: dsh plugin --profile {0} install" -f $DshProfile) -ForegroundColor Yellow
    }
} else {
    Write-Host 'profile  = (default: web - the global charter IS injected)'
}
if (-not (Test-Path (Join-Path $root 'tts\config.ps1'))) {
    Write-Host 'WARN: tts\config.ps1 not found under this project root.' -ForegroundColor Yellow
}
if ($NoLaunch) { Write-Host '(-NoLaunch: set the variable only; nothing started)'; return }
Write-Host ("launching: " + $DshCommand)
& powershell -NoProfile -Command $DshCommand
