# say.ps1 - append ONE message to the TTS dialogue tab as a rolling window.
#
# WHY: the notebook tab only grows. Rewriting the whole body each turn meant every
# later tabread paid to echo all of it. This script:
#   1. reads the current body tail
#   2. archives that tail to logs\channel_archive.txt (full history on disk; never
#      read unless deliberately asked for)
#   3. keeps only the last -KeepChars characters plus the new message
#   4. writes it back and verifies
# So the in-game channel stays a readable window instead of an ever-growing document.
#
# USAGE
#   say.ps1 -MessageFile C:\path\msg.txt      # Chinese text MUST go through a file
#   say.ps1 -Message 'short one-liner'
# NOTE: param() must stay the FIRST statement in this file; the config dot-source comes after.
param(
    [string]$MessageFile = '',
    [string]$Message = '',
    [int]$KeepChars = 600,
    [string]$Ds = '',
    [string]$Archive = ''
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($Ds -eq '')      { $Ds = Join-Path $DshTts 'ds.ps1' }
if ($Archive -eq '') { $Archive = Join-Path $DshLogs 'channel_archive.txt' }
$ErrorActionPreference = 'Stop'

$text = $Message
if ($MessageFile -ne '') {
    if (-not (Test-Path -LiteralPath $MessageFile)) { throw "no such message file: $MessageFile" }
    $text = [System.IO.File]::ReadAllText($MessageFile, [System.Text.Encoding]::UTF8)
}
if ($text.Trim() -eq '') { throw 'empty message' }

# ---- 1. read the current tail -----------------------------------------------
$readOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $Ds -Do tabread -Tail ($KeepChars + 300) 2>&1
$readLine = ($readOut | Select-Object -First 1)
if ($readLine -notmatch '^ok tabread') { throw "read failed: $readLine" }

$tail = ''
$m = [regex]::Match($readLine, '\| tail: (.*)$')
if ($m.Success) { $tail = ($m.Groups[1].Value -replace ' / ', "`n") }

# ---- 2. archive what we are about to drop -----------------------------------
if ($tail.Trim() -ne '') {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "`n===== window archived $stamp =====`n$tail`n"
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Archive) -Force -ErrorAction SilentlyContinue
    [System.IO.File]::AppendAllText($Archive, $entry, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("archived {0} chars -> {1}" -f $tail.Length, $Archive)
}

# ---- 3. compose the kept window + the new message ---------------------------
$kept = $tail
if ($kept.Length -gt $KeepChars) { $kept = $kept.Substring($kept.Length - $KeepChars) }
$sep = "`n`n----------------------------------------`n"
$new = $kept + $sep + $text

# ---- 4. write it back ------------------------------------------------------
$outDir = $DshOut
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$tmp = Join-Path $outDir 'say_body.txt'
[System.IO.File]::WriteAllText($tmp, $new, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("body = {0} chars (kept {1} + new {2})" -f $new.Length, $kept.Length, $text.Length)
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $Ds -Do 'tabwrite' -TextFile $tmp 2>&1
Write-Host ($out -join "`n")
