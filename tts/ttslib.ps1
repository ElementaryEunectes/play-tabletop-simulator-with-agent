# ttslib.ps1 - the ONE copy of the TTS TCP transport. DOT-SOURCE it, never spawn it.
#
# WHY THIS EXISTS
#   ttsx.ps1, channel_watch.ps1 and the inline snippets all need the same 30 lines of
#   socket code, and every copy is a chance to re-introduce the messageID-4 bug. More
#   importantly: the sandbox kills the network of NESTED child processes, so a watcher
#   that spawns ds.ps1 (level 2) fails wholesale while a dot-source (same process) is fine.
#
# CONTRACT
#   . "$PSScriptRoot\ttslib.ps1"
#   $r = Invoke-Tts -Envelope '{"messageID":2,"customMessage":{"cmd":"ping"}}'
#   $r.err      -> $null, or 'PORTCLOSED' | 'LISTENERBUSY' | 'NOREPLY'
#   $r.custom   -> the customMessage object (only for messageID 4 replies)
#   $r.raw      -> the raw reply packet
#
# ASCII only, except comments. Chinese comments require the UTF-8 BOM: run check_ps1.ps1.

function Invoke-Tts {
    param(
        [Parameter(Mandatory=$true)][string]$Envelope,
        [int]$TimeoutSec = 8,
        [int]$Retries = 3,
        [int]$TtsPort = 39999
    )
    $ED = 39998

    # Bind the callback port. A background watcher may hold 39998 for a moment, so retry
    # briefly, then report LISTENERBUSY - which is a DIFFERENT fault from "TTS is closed"
    # and must never be reported as one.
    $listener = $null
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $ED)
            $listener.Start()
            break
        } catch {
            $listener = $null
            Start-Sleep -Milliseconds 400
        }
    }
    if ($null -eq $listener) { return @{ err = 'LISTENERBUSY' } }

    $c = [System.Net.Sockets.TcpClient]::new()
    try {
        $c.Connect('127.0.0.1', $TtsPort)
        $b = [System.Text.Encoding]::UTF8.GetBytes($Envelope)
        $s = $c.GetStream(); $s.Write($b, 0, $b.Length); $s.Flush()
    } catch {
        try { $listener.Stop() } catch {}
        return @{ err = 'PORTCLOSED' }   # 39999 refused. NOT a verdict on the TTS process.
    }
    # Keep the socket OPEN and poll from t=0: closing early races TTS's read of our bytes.

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $skipped = 0
    $raw = $null
    while ((Get-Date) -lt $deadline) {
        $pending = $false
        try { $pending = $listener.Pending() } catch { break }
        if (-not $pending) { Start-Sleep -Milliseconds 15; continue }

        $rc = $listener.AcceptTcpClient()
        $rs = $rc.GetStream()
        $rs.ReadTimeout = 1500
        $ms = [System.IO.MemoryStream]::new()
        try {
            $buf = New-Object byte[] 65536
            while ($true) {
                $n = $rs.Read($buf, 0, $buf.Length)
                if ($n -le 0) { break }
                $ms.Write($buf, 0, $n)
            }
        } catch {}
        $pkt = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
        try { $rc.Close() } catch {}

        $id = -1
        try { $id = [int](($pkt | ConvertFrom-Json).messageID) } catch {}
        if ($id -eq 4 -or $id -eq -1) { $raw = $pkt; break }
        $skipped++      # messageID 5 = load, 6 = autosave: unrelated push, drop it
    }

    try { $listener.Stop() } catch {}
    try { $c.Close() } catch {}

    if ($null -eq $raw) { return @{ err = 'NOREPLY'; skipped = $skipped } }
    $custom = $null
    try { $custom = ($raw | ConvertFrom-Json).customMessage } catch {}
    return @{ err = $null; raw = $raw; custom = $custom; skipped = $skipped }
}

# Wrap a bare command object into the messageID 2 envelope.
# Repair-BareJson exists because `powershell -File script.ps1 -Cmd '{"cmd":"ping"}'`
# STRIPS the inner double quotes, delivering the bare word {cmd:ping}. Both forms work.
function Repair-BareJson([string]$s) {
    $s = $s -replace '([{,]\s*)([A-Za-z_][\w]*)(\s*:)', '$1"$2"$3'
    $s = $s -replace '(:\s*)([A-Za-z_][\w]*)(\s*[,}])', '$1"$2"$3'
    return $s
}

function New-TtsEnvelope {
    param([Parameter(Mandatory=$true)][string]$Cmd)
    $obj = $null
    try { $obj = $Cmd | ConvertFrom-Json } catch { $obj = $null }
    if ($null -eq $obj) {
        try { $obj = (Repair-BareJson $Cmd) | ConvertFrom-Json } catch { return $null }
    }
    if ($obj.PSObject.Properties.Name -contains 'messageID') {
        return ($obj | ConvertTo-Json -Depth 10 -Compress)
    }
    return (@{ messageID = 2; customMessage = $obj } | ConvertTo-Json -Depth 10 -Compress)
}

function New-TtsExecEnvelope {
    param(
        [Parameter(Mandatory=$true)][string]$Guid,
        [Parameter(Mandatory=$true)][string]$Lua
    )
    return (@{ messageID = 3; guid = $Guid; script = $Lua } | ConvertTo-Json -Depth 10 -Compress)
}
