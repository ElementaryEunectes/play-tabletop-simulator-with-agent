# config.ps1 - resolve every machine-specific path ONCE, so the scripts are portable.
#
# WHY THIS EXISTS
#   Every script used to carry C:\Users\<name>\... as a parameter default, so a clone
#   could not run anywhere else. Now each script dot-sources this file and defaults to
#   these variables instead.
#
# OVERRIDE WITHOUT EDITING FILES (recommended): set environment variables first
#   $env:DSH_HOME        = 'D:\somewhere\tts-agent'  # workspace root = this project (holds cache\, out\, logs\, shots\)
#   $env:TTS_SAVES_DIR   = 'D:\...\Saves'            # Tabletop Simulator saves folder
#   $env:TTS_IMAGES_DIR  = 'D:\...\Mods\Images'      # TTS image cache
# Everything has a sane fallback, so no variable is required.

# NOTE: these vars are rebuilt from scratch on every dot-source. If a caller already had
# a stale value in scope (an earlier dot-source of another copy of config.ps1), the old
# code silently kept it -> scripts resolved paths to a directory that no longer existed.
# Clear first, then decide.
#
# RESOLUTION ORDER (this exact order matters, it cost a whole debugging round):
#   1. a directory from $env:DSH_HOME that ACTUALLY holds this project (tts\config.ps1)
#   2. this file's own location: <workspace>\tts\config.ps1 -> the workspace is its parent
#   3. $env:DSH_HOME as-is (harness home that has no tts\ yet)
#   4. <user profile>\.dsh (last-resort legacy default)
# Step 1 before 2 is what lets a moved project keep working even when the environment
# still points at an older DSH_HOME.
Remove-Variable WorkspaceRoot -ErrorAction SilentlyContinue
Remove-Variable TtsSavesDir   -ErrorAction SilentlyContinue
Remove-Variable TtsImagesDir  -ErrorAction SilentlyContinue
# Re-seed the two optional vars as EMPTY. Callers may run with Set-StrictMode -Version 2.0
# (play.ps1 does), where merely READING an unset variable is a hard error - and the branches
# below read them. Empty is falsy, so the semantics are identical to "unset".
$TtsSavesDir  = ''
$TtsImagesDir = ''
$SelfRoot = Split-Path -Parent $PSScriptRoot          # <workspace> (this file is <workspace>\tts\config.ps1)
if ($env:DSH_HOME -and (Test-Path (Join-Path $env:DSH_HOME 'tts\config.ps1'))) {
    $WorkspaceRoot = $env:DSH_HOME
} elseif (Test-Path (Join-Path $SelfRoot 'tts\config.ps1')) {
    $WorkspaceRoot = $SelfRoot
} elseif ($env:DSH_HOME) {
    $WorkspaceRoot = $env:DSH_HOME
} else {
    $WorkspaceRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh'
}
$DshTts   = Join-Path $WorkspaceRoot 'tts'
$DshCache = Join-Path $WorkspaceRoot 'cache'
$DshOut   = Join-Path $WorkspaceRoot 'out'
$DshLogs  = Join-Path $WorkspaceRoot 'logs'
$DshShots = Join-Path $WorkspaceRoot 'shots'

$Docs = [Environment]::GetFolderPath('MyDocuments')
if (-not $TtsSavesDir) {
    if ($env:TTS_SAVES_DIR) { $TtsSavesDir = $env:TTS_SAVES_DIR }
    else {
        $TtsSavesDir = Join-Path $Docs 'My Games\Tabletop Simulator\Saves'
        if (-not (Test-Path $TtsSavesDir)) { $TtsSavesDir = Join-Path $Docs 'Tabletop Simulator\Saves' }
    }
}
if (-not $TtsImagesDir) {
    if ($env:TTS_IMAGES_DIR) { $TtsImagesDir = $env:TTS_IMAGES_DIR }
    else {
        $TtsImagesDir = Join-Path $Docs 'My Games\Tabletop Simulator\Mods\Images'
        if (-not (Test-Path $TtsImagesDir)) { $TtsImagesDir = Join-Path $Docs 'Tabletop Simulator\Mods\Images' }
    }
}

# --- WHICH GAME IS CURRENT (appended 2026-10-08) ----------------------------------------------
# Never hard-code a game name in a script. It comes from the machine-readable GAME= line in
# local\games\_current.md (gitignored: local content, not toolkit code). A clone that has never
# played anything gets '' and game-dependent scripts can fail with a clear message instead of
# silently reading some other game's data.
Remove-Variable DshGame      -ErrorAction SilentlyContinue
Remove-Variable DshGameDir   -ErrorAction SilentlyContinue
Remove-Variable DshGameRules -ErrorAction SilentlyContinue
Remove-Variable DshGameCards -ErrorAction SilentlyContinue
Remove-Variable DshGameAlias -ErrorAction SilentlyContinue
Remove-Variable DshGameObjects -ErrorAction SilentlyContinue
$DshLocalGames = Join-Path $WorkspaceRoot 'local\games'
$DshGame = ''
$CurrentPointer = Join-Path $DshLocalGames '_current.md'
if (Test-Path -LiteralPath $CurrentPointer) {
    foreach ($line in [System.IO.File]::ReadAllLines($CurrentPointer, [System.Text.Encoding]::UTF8)) {
        if ($line -match '^\s*GAME\s*=\s*([A-Za-z0-9_.-]+)\s*$') { $DshGame = $Matches[1]; break }
    }
}
$DshGameDir   = if ($DshGame -ne '') { Join-Path $DshLocalGames $DshGame } else { '' }
$DshGameRules = if ($DshGame -ne '') { Join-Path $DshCache ($DshGame + '_rules.json') } else { '' }
$DshGameCards = if ($DshGame -ne '') { Join-Path $DshCache ($DshGame + '_cards.md') } else { '' }
# Two more per-game files, added 2026-10-09 so that "which game" is decided in exactly ONE place:
#   *_alias.json  = what the player says ("hex", "bow") -> which card name that means. GAME DATA,
#                   hand-written, so it sits with the other generated per-game cache files.
#   objects.json  = what to recognise on the table (image hashes / nicknames / labels / seat rule).
#                   GAME DATA too, but it belongs to the game's own folder: local\games\<game>\.
$DshGameAlias   = if ($DshGame -ne '') { Join-Path $DshCache ($DshGame + '_alias.json') } else { '' }
$DshGameObjects = if ($DshGameDir -ne '') { Join-Path $DshGameDir 'objects.json' } else { '' }

# --- THE GENERIC PRIMITIVE LAYER (added 2026-10-09) --------------------------------------------
# WHERE THE TWO LAYERS ARE SPLIT, in one place:
#   tts\      = GENERIC PRIMITIVES: talk to TTS, read/index/diff, recognise objects, query cards,
#               write the save. Nothing in there may know a game's rules, seats or board.
#   local\games\<game>\control\ = THAT GAME'S CONTROL LAYER: verbs, skill tables, counters, dice
#               trays - the part a user TRAINS per mod. Not in the repository, never shipped.
# tts\play.ps1 stays in the repo but is only a DISPATCHER: it dot-sources the controller named
# here. So "add a game" = add files here + point the GAME= line at it, with no edit to the repo.
$DshGameControl = if ($DshGameDir -ne '') { Join-Path $DshGameDir 'control\play.ps1' } else { '' }
# The transport modules the generic layer exposes to any controller (config owns the paths, so no
# control-layer script ever hard-codes a repo path). Load ORDER matters: ttslib is the TCP transport
# (Invoke-Tts), bridge.ps1 is the thin reply-checking wrapper on top of it.
$DshLibTtslib   = Join-Path $WorkspaceRoot 'tts\ttslib.ps1'
$DshLibBridge   = Join-Path $WorkspaceRoot 'tts\lib\bridge.ps1'
