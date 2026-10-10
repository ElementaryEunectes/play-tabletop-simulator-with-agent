# tts_api.ps1 - Tabletop Simulator External Editor API client (ASCII-only on purpose)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tts_api.ps1 -Action getscripts
#   powershell -ExecutionPolicy Bypass -File tts_api.ps1 -Action exec -Guid "-1" -Lua "print(1)"
#   powershell -ExecutionPolicy Bypass -File tts_api.ps1 -Action setglobal -Lua "print('hi')"
#
# Protocol: TTS listens on 39999, editor connects as TCP client.
# Editor also listens on 39998 to receive TTS replies:
#   TTS -> editor: 1=scriptStates 2=print 3=error 4=custom 5=returnValue 6=saved 7=objectCreated
#   editor -> TTS: 0=GetScripts 1=SaveAndPlay 2=CustomMessage 3=ExecuteLua(needs guid)
# Outgoing field is "messageID". Keep this file ASCII-only: PS 5.1 reads
# BOM-less files as ANSI and non-ASCII bytes corrupt the parser.
#
# NOTE 2026-10-08: body repaired after the batch-replace incident. The damage pattern was:
# "$" -> "i", ")" deleted (including in "@()"), "'" -> "C", "J" deleted (JSON -> SON), plus
# one hardcoded C:\Users\... output path. Damage was PATCHY - clean and corrupt lines were
# interleaved - so never "fix" this file by search/replace; audit it line by line and run
# check_ps1.ps1 afterwards.

param(
    [ValidateSet('getscripts','exec','setglobal','watch')]
    [string]$Action = 'getscripts',
    [string]$Guid = '-1',
    [string]$Lua  = '',
    [string]$Out  = '',
    [string]$RawJson = '',
    [switch]$RawStdin,
    [int]$ListenSec = 15
)
. (Join-Path $PSScriptRoot 'config.ps1')
# param() must stay the first statement, so the default is resolved here, after config.ps1
# has defined $DshCache (never reference config variables inside param() defaults).
if ($Out -eq '') { $Out = (Join-Path $DshCache 'tts_scripts_raw.json') }
# Guard: -Out must be a usable file path. Measured 2026-10-11: a multi-line script passed on the
# command line got shifted into -Out by the outer shell, and the "save the reply" step then died with
# "Illegal characters in path" - AFTER the message had already been sent, which reads like a send
# failure. Fall back to the default instead of throwing.
if ($Out -match '[\r\n:*?"<>|]') {
    Write-Host '  WARN -Out looks like script text, not a path; using the default output file'
    $Out = (Join-Path $DshCache 'tts_scripts_raw.json')
}

$ErrorActionPreference = 'Stop'
$TtsPort    = 39999
$EditorPort = 39998

function Save-Text {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Read-Available {
    param($Stream, [int]$WaitMs)
    $buf = New-Object byte[] 524288
    $sb  = New-Object System.Text.StringBuilder
    $sw  = [System.Diagnostics.Stopwatch]::StartNew()
    $Stream.ReadTimeout = 1000
    while ($sw.ElapsedMilliseconds -lt $WaitMs) {
        try {
            if ($Stream.DataAvailable) {
                $n = $Stream.Read($buf, 0, $buf.Length)
                if ($n -le 0) { break }
                [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $n))
                $sw.Restart()
            } else {
                Start-Sleep -Milliseconds 50
            }
        } catch { break }
    }
    return $sb.ToString()
}

function Send-Message {
    param($Stream, [hashtable]$Body)
    $json  = $Body | ConvertTo-Json -Compress -Depth 20
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Stream.Write($bytes, 0, $bytes.Length)
    $Stream.Flush()
    return $json
}

Write-Host "=== [1] open editor listener on $EditorPort ==="
$editor = $null
$editorOk = $false
try {
    $editor = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $EditorPort)
    $editor.Start()
    $editorOk = $true
    Write-Host "  listening on $EditorPort OK"
} catch {
    Write-Host "  listen FAILED: $($_.Exception.Message)"
}

Write-Host "=== [2] connect to TTS on $TtsPort ==="
$client = New-Object System.Net.Sockets.TcpClient
$client.Connect('127.0.0.1', $TtsPort)
Write-Host "  connected to $($client.Client.RemoteEndPoint)"
$stream = $client.GetStream()

if ($Action -eq 'getscripts') {
    Write-Host "=== [3] send messageID 0 (Get Lua Scripts) ==="
    $sent = Send-Message -Stream $stream -Body @{ messageID = 0 }
    Write-Host "  -> $sent"
}
elseif ($Action -eq 'exec') {
    if (-not $Lua) { Write-Host "  -Lua is empty, nothing to do" }
    else {
        Write-Host "=== [3] send messageID 3 (Execute Lua) guid=$Guid ==="
        $sent = Send-Message -Stream $stream -Body @{ messageID = 3; guid = $Guid; script = $Lua }
        Write-Host "  -> $sent"
    }
}
elseif ($Action -eq 'setglobal') {
    Write-Host "=== [3] send messageID 1 (Save & Play) installing Global script ==="
    $body = @{
        messageID = 1
        scriptStates = @(
            @{ name = 'Global'; guid = '-1'; script = $Lua; ui = '' }
        )
    }
    $sent = Send-Message -Stream $stream -Body $body
    Write-Host "  -> $($sent.Substring(0, [Math]::Min(400, $sent.Length)))..."
}
elseif ($Action -eq 'watch') {
    Write-Host "=== [3] watch mode: listening only ==="
}

if ($RawStdin) {
    Write-Host "=== [3b] read RAW json from stdin (no arg-quoting damage) ==="
    $RawJson = [Console]::In.ReadToEnd()
    Write-Host "  read $($RawJson.Length) chars"
}

if ($RawJson) {
    Write-Host "=== [3c] send RAW json ==="
    Write-Host "  -> $RawJson"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($RawJson)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
}

Write-Host "=== [4] waiting for TTS reply (max $ListenSec s) ==="
$all = New-Object System.Text.StringBuilder
$accepted = @()
$msgCount = 0
if ($editorOk) {
    $deadline = (Get-Date).AddSeconds($ListenSec)
    while ((Get-Date) -lt $deadline) {
        if ($editor.Pending()) {
            $ec = $editor.AcceptTcpClient()
            $accepted += $ec
            $msgCount++
            Write-Host "  TTS connected back on $EditorPort (connection #$msgCount)"
            $es = $ec.GetStream()
            $chunk = Read-Available -Stream $es -WaitMs 2500
            if ($chunk.Length -gt 0) {
                [void]$all.Append($chunk)
                $preview = $chunk.Substring(0, [Math]::Min(300, $chunk.Length))
                Write-Host "    chunk: $preview"
            } else {
                Write-Host "    (no data)"
            }
            $ec.Close()
        } else {
            Start-Sleep -Milliseconds 100
        }
    }
}

$inline = Read-Available -Stream $stream -WaitMs 800
if ($inline.Length -gt 0) { [void]$all.Append($inline) }

$raw = $all.ToString()
if ($raw.Length -eq 0) {
    Write-Host "  NO REPLY received."
    Write-Host "  possibilities: (a) no object in this save has a Lua script, so msg 0 has nothing to report;"
    Write-Host "                 (b) TTS could not reach editor port 39998;"
    Write-Host "                 (c) channel is one-way only."
} else {
    Write-Host "  received $($raw.Length) chars"
    $outPath = if ($Out) { $Out } else { Join-Path $DshCache 'tts_scripts_raw.json' }
    Save-Text -Path $outPath -Text $raw
    Write-Host "  saved: $outPath"
    try {
        $parsed = $raw | ConvertFrom-Json
        Write-Host "  JSON parsed OK; messageID=$($parsed.messageID)"
        if ($parsed.scriptStates) {
            Write-Host "  scriptStates count: $($parsed.scriptStates.Count)"
            $parsed.scriptStates | ForEach-Object {
                $sl = if ($_.script) { $_.script.Length } else { 0 }
                $ul = if ($_.ui) { $_.ui.Length } else { 0 }
                Write-Host ("    guid={0,-10} name='{1}' script={2} ui={3}" -f $_.guid, $_.name, $sl, $ul)
            }
        }
    } catch {
        Write-Host "  JSON parse failed: $($_.Exception.Message)"
        Write-Host ($raw.Substring(0, [Math]::Min(500, $raw.Length)))
    }
}

foreach ($c in $accepted) { try { $c.Close() } catch {} }
$client.Close()
if ($editorOk) { $editor.Stop() }
Write-Host "=== done ==="
