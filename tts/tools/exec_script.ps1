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
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\exec_script.ps1 -Guid 0e731f -LuaFile x.lua
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
if ($lua.Trim() -eq '') { Write-Host 'ERR Lua file is empty'; exit 2 }

$TtsPort = 39999
$EditorPort = 39998
$utf8 = New-Object System.Text.UTF8Encoding($false)

# reply listener first, so TTS can always reach us
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $EditorPort)
$listener.Start()
Write-Host "listening on $EditorPort"

$body = @{ messageID = 3; guid = $Guid; script = $lua } | ConvertTo-Json -Compress
$client = [System.Net.Sockets.TcpClient]::new()
$client.Connect('127.0.0.1', $TtsPort)
$stream = $client.GetStream()
$bytes = $utf8.GetBytes($body)
$stream.Write($bytes, 0, $bytes.Length)
$stream.Flush()
Write-Host ("sent {0} bytes; script was {1} chars" -f $bytes.Length, $lua.Length)

# collect whatever comes back (errors and print() show up here; the return value does not)
$deadline = (Get-Date).AddSeconds($ListenSec)
$got = 0
while ((Get-Date) -lt $deadline) {
    if (-not $listener.Pending()) { Start-Sleep -Milliseconds 150; continue }
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
