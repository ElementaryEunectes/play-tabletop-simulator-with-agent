# tts_hub.ps1 - ONE resident process owns TTS's reply port (39998); every other tool asks it instead.
#
# WHY (2026-10-11)
#   Port 39998 is a SINGLE slot: whoever talks to TTS must listen there to receive the reply, because
#   TTS connects BACK to it. So any two talkers collide ("listener busy on 39998"), and a burst of
#   short-lived listeners leaves half-open connections behind - measured four times as "no reply in
#   25s" followed by 39999 no longer listening (VALIDATION.md F14). The turn poller alone binds that
#   slot for a slice of every 2.5 s, which is enough to break a hand-over.
#   This is the hub PRIOR_ART.md points at (tts-toolkit's daemon): bind 39998 ONCE and let every other
#   tool post its envelope here on 39997. While the hub runs, nothing else may touch 39998.
#
# PROTOCOL (loopback TCP, UTF-8, one request per connection, line-delimited JSON)
#   client -> hub : {"envelope":"<exactly what you would have sent to 39999>","want":"custom"|"any","timeoutSec":N}\n
#   hub -> client : {"raw":"<the packet TTS sent back>","skipped":n,"ms":n}\n
#                   {"hubErr":"PORTCLOSED"|"NOREPLY"|"HUBERR","detail":"..."}\n
#   The hub's OWN errors are under "hubErr" on purpose: a TTS reply carries "err" of its own, and the
#   two must never be confused by a client.
#   want=custom -> first messageID 4 packet (a command reply); 2/5/6/7 pushes are skipped
#   want=any    -> first non-empty packet of any kind (messageID 3 runs: prints and errors arrive as 2/3)
#
# PORTS: 39999 is TTS's editor API, 39998 is TTS's reply channel (ours to listen on), 39997 is this
# hub's client port (the same number tts-toolkit's hub uses, so the two designs stay comparable).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\tts_hub.ps1      # run it as a background job
#
# ASCII only.
param(
    [string]$Root = '',
    [int]$ClientPort = 39997,
    [int]$EditorPort = 39998,
    [int]$TtsPort = 39999,
    [int]$ReplySec = 20,
    [int]$BindRetries = 6,
    [int]$IdleMinutes = 0
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')

function New-Listener([int]$port, [int]$retries) {
    for ($i = 1; $i -le $retries; $i++) {
        try {
            $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
            $l.Start()
            return $l
        } catch {
            Write-Host ("hub: port {0} busy, retry {1}/{2} ..." -f $port, $i, $retries)
            Start-Sleep -Milliseconds 1500
        }
    }
    return $null
}

# Read one \n-terminated line. Clients always terminate, so this never waits for EOF on a connection
# that is being kept open for the answer.
function Read-Line([System.IO.Stream]$s, [int]$timeoutMs) {
    $s.ReadTimeout = $timeoutMs
    $ms = [System.IO.MemoryStream]::new()
    $buf = New-Object byte[] 8192
    try {
        while ($true) {
            $n = $s.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $idx = -1
            for ($i = 0; $i -lt $n; $i++) { if ($buf[$i] -eq 10) { $idx = $i; break } }
            if ($idx -ge 0) { $ms.Write($buf, 0, $idx); break }
            $ms.Write($buf, 0, $n)
        }
    } catch { return $null }
    if ($ms.Length -eq 0) { return $null }
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimEnd("`r")
}

# Read a whole TTS packet: TTS sends compact JSON and closes, so read to EOF with a short idle timeout
# (same shape as ttslib.ps1's reader).
function Read-Packet([System.Net.Sockets.TcpClient]$c, [int]$readTimeoutMs) {
    $rs = $c.GetStream()
    $rs.ReadTimeout = $readTimeoutMs
    $ms = [System.IO.MemoryStream]::new()
    $buf = New-Object byte[] 65536
    try {
        while ($true) {
            $n = $rs.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $ms.Write($buf, 0, $n)
        }
    } catch { }
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
}

function Log-Hub([string]$line) {
    try {
        $f = Join-Path $DshCache 'hub.log'
        [System.IO.File]::AppendAllText($f, ((Get-Date -Format 'HH:mm:ss') + ' ' + $line + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    } catch { }
}

$editor = New-Listener $EditorPort $BindRetries
if ($null -eq $editor) {
    Write-Host ("ERR cannot listen on {0} after {1} tries - something else owns the reply port; stop it, or let that one be the hub" -f $EditorPort, $BindRetries)
    exit 3
}
$clients = New-Listener $ClientPort $BindRetries
if ($null -eq $clients) {
    try { $editor.Stop() } catch { }
    Write-Host ("ERR cannot listen on client port {0} - is another hub already running?" -f $ClientPort)
    exit 3
}
Write-Host ("hub: clients on {0} | TTS replies on {1} | sending to {2} | reply window {3}s" -f $ClientPort, $EditorPort, $TtsPort, $ReplySec)

$served = 0; $drained = 0; $lastActivity = Get-Date

while ($true) {
    if ($IdleMinutes -gt 0 -and ((Get-Date) - $lastActivity).TotalMinutes -ge $IdleMinutes) {
        Write-Host ("hub: idle for {0} min, stopping" -f $IdleMinutes)
        break
    }
    # Drain unsolicited pushes (messageID 1/2/3/5/6/7) so TTS's client never blocks on a full backlog.
    try {
        while ($editor.Pending()) {
            $rc = $editor.AcceptTcpClient()
            $null = Read-Packet $rc 400
            $rc.Close()
            $drained++
        }
    } catch { }

    if (-not $clients.Pending()) { Start-Sleep -Milliseconds 25; continue }

    $cc = $clients.AcceptTcpClient()
    $cs = $cc.GetStream()
    $req = Read-Line $cs 5000
    if ([string]::IsNullOrWhiteSpace($req)) { try { $cc.Close() } catch { }; continue }
    $lastActivity = Get-Date

    $want = 'custom'; $timeoutSec = $ReplySec; $envelope = ''; $cmd = '?'
    try {
        $r = $req | ConvertFrom-Json
        $envelope = [string]$r.envelope
        if ([string]$r.want -eq 'any') { $want = 'any' }
        if ([int]$r.timeoutSec -gt 0) { $timeoutSec = [int]$r.timeoutSec }
        # The envelope is a STRING on the wire, so the command name has to be parsed out of it for the
        # heartbeat line - reading $r.envelope.customMessage would always come back null.
        try { $cmd = [string](($r.envelope | ConvertFrom-Json).customMessage.cmd) } catch { }
        if ($cmd -eq '') { $cmd = '?' }
    } catch { }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = $null; $skipped = 0; $hubErr = ''; $detail = ''
    if ($envelope -eq '') {
        $hubErr = 'HUBERR'; $detail = 'request had no envelope'
    } else {
        $conn = $null
        try {
            $conn = [System.Net.Sockets.TcpClient]::new()
            $conn.Connect('127.0.0.1', $TtsPort)
        } catch {
            $conn = $null
            $hubErr = 'PORTCLOSED'
        }
        if ($null -ne $conn) {
            try {
                $b = [System.Text.Encoding]::UTF8.GetBytes($envelope)
                $ts = $conn.GetStream(); $ts.Write($b, 0, $b.Length); $ts.Flush()
                $deadline = (Get-Date).AddSeconds($timeoutSec)
                while ((Get-Date) -lt $deadline) {
                    if (-not $editor.Pending()) { Start-Sleep -Milliseconds 15; continue }
                    $rc = $editor.AcceptTcpClient()
                    $pkt = Read-Packet $rc 1500
                    $rc.Close()
                    if ($pkt -eq '') { continue }
                    if ($want -eq 'any') { $raw = $pkt; break }
                    $id = -1
                    try { $id = [int](($pkt | ConvertFrom-Json).messageID) } catch { }
                    if ($id -eq 4 -or $id -eq -1) { $raw = $pkt; break }
                    $skipped++
                }
                if ($null -eq $raw -and $hubErr -eq '') { $hubErr = 'NOREPLY' }
            } catch {
                $hubErr = 'HUBERR'; $detail = ($_.Exception.Message -replace '"', "'")
            }
            try { $conn.Close() } catch { }
        }
    }
    $sw.Stop()

    if ($hubErr -ne '') {
        $out = (@{ hubErr = $hubErr; detail = $detail; skipped = $skipped; ms = [int]$sw.ElapsedMilliseconds } | ConvertTo-Json -Compress -Depth 5)
        Log-Hub ("cmd={0} {1} {2}" -f $cmd, $hubErr, $detail)
    } else {
        $out = (@{ raw = $raw; skipped = $skipped; ms = [int]$sw.ElapsedMilliseconds } | ConvertTo-Json -Compress -Depth 5)
    }
    try {
        $b = [System.Text.Encoding]::UTF8.GetBytes($out + "`n")
        $cs.Write($b, 0, $b.Length); $cs.Flush()
    } catch { }
    try { $cc.Close() } catch { }

    $served++
    $flag = if ($hubErr -ne '') { ' ' + $hubErr } else { '' }
    Write-Host ("hub: #{0} cmd={1} skipped={2} {3}ms{4}" -f $served, $cmd, $skipped, [int]$sw.ElapsedMilliseconds, $flag)
}

try { $editor.Stop() } catch { }
try { $clients.Stop() } catch { }
Write-Host ("hub: stopped (served {0}, drained {1} pushes)" -f $served, $drained)
exit 0
