# setup.ps1 - the wizard for a first run: check the machine, scaffold a new game, show the path to a
# first completed round.
#
# WHY IT EXISTS
#   doctor.ps1 answers "is this machine ready and what will the context cost". That is necessary and not
#   sufficient: a stranger still has to know WHAT to do in what order, and someone starting a new mod has
#   to create four files by hand before anything works. This script covers both without duplicating the
#   environment checks - it calls doctor.ps1 for those.
#
# READ-ONLY BY DEFAULT. The only writes are behind -InitGame, and they go under local\games\ (gitignored,
# never shipped) plus the GAME= line of local\games\_current.md, which is backed up first.
#
# ASCII output on purpose: it is meant to run on somebody else's computer.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\setup.ps1                     # guide + doctor
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\setup.ps1 -DryRun 1 -InitGame mymod
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\setup.ps1 -InitGame mymod     # scaffold
param(
    [string]$Root = '',
    [string]$InitGame = '',
    [switch]$Force,
    [int]$DryRun = 0
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
. (Join-Path $Root 'tts\config.ps1')

$TemplateDir = Join-Path $Root 'tts\templates'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Show-Path {
    Write-Host ''
    Write-Host '== path to a first completed round =='
    Write-Host '  1. install      Windows + PowerShell 5.1, Node.js, then:  npm i -g @deepseek-ai/dsh'
    Write-Host '  2. TTS          Steam, then subscribe to the target mod (Workshop)'
    Write-Host '  3. scaffold     tts\setup.ps1 -InitGame <slug>        (creates local\games\<slug>\)'
    Write-Host '  4. bake bridge  tts\docs\BOOTSTRAP.md section 2        (install_save2.ps1 -DryRun first)'
    Write-Host '  5. reload       player loads that save in TTS, then:  tts\ds.ps1 -Do ping'
    Write-Host '  6. index        tts\obj_index.ps1 -File <save.json> ; tts\bootstrap.ps1 -Inventory'
    Write-Host '  7. calibrate    tts\tools\turn_calib.ps1 -Discover ; -Answer mine|player'
    Write-Host '  8. play         tts\play.ps1 status   (works with or without a control layer)'
    Write-Host ''
    Write-Host '  Time to a first round: roughly 1 to 1.5 hours, and about half of it is step 6-7.'
    Write-Host '  Full detail: README.md (first-run costs) and tts\docs\BOOTSTRAP.md.'
}

# ---------------------------------------------------------------- scaffold a new game
if ($InitGame -ne '') {
    if ($InitGame -notmatch '^[A-Za-z0-9_.-]+$') {
        Write-Host ("ERR the slug must match [A-Za-z0-9_.-]+ (config.ps1 reads GAME= with that pattern); got: " + $InitGame)
        exit 2
    }
    if (-not (Test-Path -LiteralPath $TemplateDir)) { Write-Host ("ERR no templates at " + $TemplateDir); exit 2 }

    $gameDir = Join-Path $DshLocalGames $InitGame
    $pointer = Join-Path $DshLocalGames '_current.md'
    $files = @('STATE.template.md', 'FLOW.template.md', 'MYHAND.template.md')

    Write-Host ("scaffold game '" + $InitGame + "'")
    Write-Host ("  dir      " + $gameDir)
    Write-Host ("  from     " + $TemplateDir)
    Write-Host ("  pointer  " + $pointer)

    if ((Test-Path -LiteralPath $gameDir) -and -not $Force) {
        Write-Host 'ERR that game directory already exists - pass -Force to overwrite its templates'
        exit 2
    }
    $missing = @($files | Where-Object { -not (Test-Path -LiteralPath (Join-Path $TemplateDir $_)) })
    if ($missing.Count -gt 0) { Write-Host ('ERR missing template(s): ' + ($missing -join ', ')); exit 2 }

    if ($DryRun -eq 1) {
        Write-Host 'WILL WRITE (dry run, nothing written):'
        foreach ($f in $files) { Write-Host ('  ' + (Join-Path $gameDir ($f -replace '\.template\.md$', '.md'))) }
        Write-Host ('  GAME=' + $InitGame + '   in ' + $pointer)
        exit 0
    }

    New-Item -ItemType Directory -Force -Path $gameDir | Out-Null
    foreach ($f in $files) {
        $target = Join-Path $gameDir ($f -replace '\.template\.md$', '.md')
        $text = [System.IO.File]::ReadAllText((Join-Path $TemplateDir $f), [System.Text.Encoding]::UTF8)
        # the templates use <游戏> as the placeholder for the slug (it appears in cache\<游戏>_cards.md paths)
        $text = $text.Replace('<游戏>', $InitGame)
        [System.IO.File]::WriteAllText($target, $text, $Utf8NoBom)
        Write-Host ('  wrote ' + $target)
    }

    # point the current-game file at the new slug, backing it up first
    if (Test-Path -LiteralPath $pointer) {
        Copy-Item -LiteralPath $pointer -Destination ($pointer + '.bak') -Force
        $lines = [System.IO.File]::ReadAllLines($pointer, [System.Text.Encoding]::UTF8)
        $done = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*GAME\s*=') { $lines[$i] = 'GAME=' + $InitGame; $done = $true; break }
        }
        if (-not $done) { $lines = @('GAME=' + $InitGame) + $lines }
        [System.IO.File]::WriteAllLines($pointer, $lines, $Utf8NoBom)
        Write-Host ('  updated ' + $pointer + '  (backup: ' + $pointer + '.bak)')
    } else {
        [System.IO.File]::WriteAllText($pointer, ("GAME=" + $InitGame + "`n"), $Utf8NoBom)
        Write-Host ('  created ' + $pointer)
    }

    Write-Host ''
    Write-Host ('next: read local\games\' + $InitGame + '\STATE.md, then tts\docs\BOOTSTRAP.md section 2.')
    exit 0
}

# ---------------------------------------------------------------- default: guide + doctor
Show-Path
$doctor = Join-Path $Root 'tts\doctor.ps1'
if (Test-Path -LiteralPath $doctor) {
    Write-Host ''
    Write-Host '== environment check (tts\doctor.ps1) =='
    & powershell -NoProfile -ExecutionPolicy Bypass -File $doctor
}
exit 0
