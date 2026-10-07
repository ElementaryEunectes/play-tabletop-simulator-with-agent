# say.ps1 - append ONE message to the TTS dialogue tab as a rolling window.
#
# WHY: the notebook tab only grows. Rewriting the whole body each turn meant every
# later tabread paid to echo all of it. This script:
#   1. reads the current body
#   2. archives that tail to logs\channel_archive.txt (full history on disk; never
#      read unless deliberately asked for)
#   3. keeps only the last -KeepChars characters plus the new message
#   4. writes it back and verifies
# So the in-game channel stays a readable window instead of an ever-growing document.
#
# 2026-10-08: this used to spawn `powershell -File ds.ps1` twice (once to read, once to
# write) = two extra process starts (~0.35s each) per message, on the hottest comms path
# there is. It now dot-sources ttslib.ps1 and talks TCP in its own process, exactly like
# channel_watch.ps1 does. The bridge replies carry fields, so the old regex parsing of
# ds.ps1's one-line output is gone too.
#
# USAGE
#   say.ps1 -MessageFile C:\path\msg.txt      # Chinese text MUST go through a file
#   say.ps1 -Message 'short one-liner'
# NOTE: param() must stay the FIRST statement in this file; the config dot-source comes after.
param(
    [string]$MessageFile = '',
    [string]$Message = '',
    [int]$KeepChars = 600,
    [string]$TtsLib = '',
    [string]$Archive = ''
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($TtsLib  -eq '') { $TtsLib  = Join-Path $DshTts 'ttslib.ps1' }
if ($Archive -eq '') { $Archive = Join-Path $DshLogs 'channel_archive.txt' }
$ErrorActionPreference = 'Stop'

$text = $Message
if ($MessageFile -ne '') {
    if (-not (Test-Path -LiteralPath $MessageFile)) { throw "no such message file: $MessageFile" }
    $text = [System.IO.File]::ReadAllText($MessageFile, [System.Text.Encoding]::UTF8)
}
if ($text.Trim() -eq '') { throw 'empty message' }

# ttslib.ps1 is the ONE copy of the TTS TCP transport. Dot-source it: same process, one
# level deep. (Spawning a helper is what the sandbox kills: dsh -> dsh -> script.)
if (-not (Test-Path -LiteralPath $TtsLib)) { throw "ttslib.ps1 not found at $TtsLib" }
. $TtsLib

function Send-Tts {
    param([hashtable]$Cmd, [int]$Retries = 4)
    $envelope = @{ messageID = 2; customMessage = $Cmd } | ConvertTo-Json -Depth 8 -Compress
    for ($i = 1; $i -le $Retries; $i++) {
        $r = Invoke-Tts -Envelope $envelope
        if ($r.err -eq 'LISTENERBUSY') { Start-Sleep -Milliseconds 400; continue }
        if ($r.err) { throw ("bridge error: " + $r.err + " (cmd=" + $Cmd.cmd + ")") }
        if ($null -eq $r.custom) { throw ("reply from TTS was not JSON (cmd=" + $Cmd.cmd + ")") }
        if ($r.custom.ok -ne $true) {
            $e = 'unknown'
            if ($null -ne $r.custom.err) { $e = [string]$r.custom.err }
            throw ("cmd=" + $Cmd.cmd + " rejected by bridge: " + $e)
        }
        return $r.custom
    }
    throw ("listener stayed busy (cmd=" + $Cmd.cmd + ")")
}

# ---- 1. read the current body -----------------------------------------------
$resp = Send-Tts @{ cmd = 'tabread' }
$body = ''
if ($null -ne $resp.PSObject.Properties['body'] -and $null -ne $resp.body) { $body = [string]$resp.body }
$title = ''
if ($null -ne $resp.PSObject.Properties['title'] -and $null -ne $resp.title) { $title = [string]$resp.title }
Write-Host ("tabread chars={0} title={1}" -f $body.Length, $title)

# ---- 2. archive what we are about to drop -----------------------------------
if ($body.Trim() -ne '') {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "`n===== window archived $stamp =====`n$body`n"
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Archive) -Force -ErrorAction SilentlyContinue
    [System.IO.File]::AppendAllText($Archive, $entry, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("archived {0} chars -> {1}" -f $body.Length, $Archive)
}

# ---- 3. compose the kept window + the new message ---------------------------
$kept = $body
if ($kept.Length -gt $KeepChars) { $kept = $kept.Substring($kept.Length - $KeepChars) }
$sep = "`n`n----------------------------------------`n"
$new = $kept + $sep + $text

# ---- 4. write it back and check the bridge's own verification ---------------
$out = Send-Tts @{ cmd = 'tabwrite'; text = $new }
Write-Host ("tabwrite sent={0} readback={1} verified={2}" -f $out.sentChars, $out.readbackChars, $out.verified)
if ($out.verified -ne $true) { throw 'tabwrite was not verified by the bridge' }
