# exec_script.ps1 - run a Lua FILE inside an object's own script environment.
#
# WHY A FILE, AND WHY THIS FILE TALKS TCP DIRECTLY
#   * A multi-line script passed on the command line gets mangled by the tool shell.
#   * Passing the script as a PowerShell string ARGUMENT mangles it further: measured 2026-10-11,
#     `print("QT1")` reached TTS as `print(QT1)` - the quotes were eaten by parameter handling, so Lua
#     saw an undeclared global and printed nil. Reading the bytes from a file and writing them straight
#     to the socket is the only carrier that survives intact.
#   * This path is SAFE where Object.call is not: executing forwardOneTurn() this way returned the
#     mod's own Lua error and left TTS healthy, while the same function through the bridge's callx
#     (o.call) made the API unreachable twice. See VALIDATION F12.
#
# NOTE ON RESULTS: TTS does not send the script's return value back to this listener (messageID 5 is
# documented but never arrives here). To see anything, the script itself must print() or call
# sendExternalMessage() - those arrive as messageID 2 / 4.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\exec_script.ps1 -Guid <tracker guid> -LuaFile x.lua
#
# A .lua file cannot take a parameter, and a per-match guid must not be baked into a tracked file
# (2026-10-11): if the file contains the literal __GUID__, it is replaced with this call's -Guid
# before the script is sent. That is how tools\tracker_read.lua stays generic.
param(
    [string]$Root = '',
    [Parameter(Mandatory = $true)][string]$Guid,
    [Parameter(Mandatory = $true)][string]$LuaFile,
    [int]$ListenSec = 12
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }

if (-not (Test-Path -LiteralPath $LuaFile)) { Write-Host "ERR no such Lua file: $LuaFile"; exit 2 }
$lua = [System.IO.File]::ReadAllText((Resolve-Path $LuaFile), [System.Text.Encoding]::UTF8)
$lua = $lua.Replace('__GUID__', $Guid)
if ($lua.Trim() -eq '') { Write-Host 'ERR Lua file is empty'; exit 2 }

$TtsPort = 39999
$EditorPort = 39998
$utf8 = New-Object System.Text.UTF8Encoding($false)

# reply listener first, so TTS can always reach us.
#
# RETRY THE BIND. Measured 2026-10-11: two of these in quick succession can collide - the previous
# listener's socket is still in TIME_WAIT and the bind throws, which looked like "the hand-over silently
# did nothing" because the script had already exited before sending. Three attempts with a short pause
# removes the flakiness.
$listener = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $EditorPort)
        $listener.Start()
        break
    } catch {
        if ($attempt -eq 3) { Write-Host "ERR cannot listen on $EditorPort after 3 attempts: $($_.Exception.Message)"; exit 3 }
        Write-Host "  listener busy on $EditorPort, retry $attempt/3 ..."
        Start-Sleep -Milliseconds 1500
        $listener = $null
    }
}
Write-Host "listening on $EditorPort"

$body = @{ messageID = 3; guid = $Guid; script = $lua } | ConvertTo-Json -Compress
$client = [System.Net.Sockets.TcpClient]::new()
$client.Connect('127.0.0.1', $TtsPort)
$stream = $client.GetStream()
$bytes = $utf8.GetBytes($body)
$stream.Write($bytes, 0, $bytes.Length)
$stream.Flush()
Write-Host ("sent {0} bytes; script was {1} chars" -f $bytes.Length, $lua.Length)

# Collect whatever comes back (errors and print() show up here; the return value does not).
#
# EXIT ON THE FIRST REPLY, do not sit out the whole window. Measured 2026-10-11: this loop was the reason
# `tr.ps1` took 12.9 s instead of ~1 s - the caller only needs the confirmation, and waiting for a second
# message that usually never comes just adds latency to every hand-over. A short grace period after the
# first reply still catches a following sendExternalMessage.
$deadline = (Get-Date).AddSeconds($ListenSec)
$got = 0
while ((Get-Date) -lt $deadline) {
    if (-not $listener.Pending()) {
        if ($got -gt 0) { break }              # already answered - stop waiting
        Start-Sleep -Milliseconds 60
        continue
    }
    $conn = $listener.AcceptTcpClient()
    $conn.ReceiveTimeout = 3000
    $rs = $conn.GetStream()
    $buf = New-Object byte[] 65536
    $sb = New-Object System.Text.StringBuilder
    try {
        while ($true) {
            $n = $rs.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            [void]$sb.Append($utf8.GetString($buf, 0, $n))
            if (-not $rs.DataAvailable) { break }
        }
    } catch { }
    $conn.Close()
    if ($sb.Length -gt 0) {
        $got++
        Write-Host '--- reply ---'
        Write-Host $sb.ToString()
    }
}
$client.Close()
$listener.Stop()
Write-Host ("done; replies=$got")
exit 0
