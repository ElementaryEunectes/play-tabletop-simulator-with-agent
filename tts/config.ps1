# config.ps1 - resolve every machine-specific path ONCE, so the scripts are portable.
#
# WHY THIS EXISTS
#   Every script used to carry C:\Users\<name>\... as a parameter default, so a clone
#   could not run anywhere else. Now each script dot-sources this file and defaults to
#   these variables instead.
#
# OVERRIDE WITHOUT EDITING FILES (recommended): set environment variables first
#   $env:DSH_HOME        = 'D:\somewhere\.dsh'     # workspace root (cache\, out\, logs\, shots\)
#   $env:TTS_SAVES_DIR   = 'D:\...\Saves'          # Tabletop Simulator saves folder
#   $env:TTS_IMAGES_DIR  = 'D:\...\Mods\Images'    # TTS image cache
# Everything has a sane fallback, so no variable is required.

if (-not $DshHome) {
    if ($env:DSH_HOME) { $DshHome = $env:DSH_HOME }
    elseif (Test-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'tts')) { $DshHome = Split-Path -Parent $PSScriptRoot }  # tts\ lives inside the workspace
    else { $DshHome = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh' }
}
$DshTts   = Join-Path $DshHome 'tts'
$DshCache = Join-Path $DshHome 'cache'
$DshOut   = Join-Path $DshHome 'out'
$DshLogs  = Join-Path $DshHome 'logs'
$DshShots = Join-Path $DshHome 'shots'

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
