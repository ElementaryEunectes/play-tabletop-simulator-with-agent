# turn_poller.ps1 - fast, push-style turn detection for the table's tracker.
#
# WHY: the command sentinel is capped at ~20s per probe (measured: 15s requested, 20s actual), so a
# hand-over waited up to 20s before the agent even learned about it. Polling here is cheaper than polling
# there: this loop reads the side every few seconds, writes the CURRENT side into one file, and a FILE
# sentinel (inotify push, reacts in well under a second) fires on the pattern. Detection drops from ~20s
# to about one poll interval.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\turn_poller.ps1 -IntervalSec 2.5
#
# Run it as a background job. It is NOT durable across sessions - re-start it (and re-register the file
# sentinel) in a new session; the watch note says so.
param(
    [string]$Root = '',
    [double]$IntervalSec = 2.5,
    [int]$Minutes = 0,          # 0 = run until killed
    [string]$OutFile = ''
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')
if ($OutFile -eq '') { $OutFile = Join-Path $DshCache 'turn_side.txt' }

$side = Join-Path $Root 'tts\tools\turn_side.ps1'
$stopAt = if ($Minutes -gt 0) { (Get-Date).AddMinutes($Minutes) } else { [datetime]::MaxValue }

# TWO GUARDS AGAINST ORPHANS (2026-10-11). A poller whose session was archived keeps looping forever:
# it spends the (short-lived) TTS API window every 2.5 s and its owner can no longer kill it - measured
# once, an orphan from an archived session kept a window from ever staying open.
#   * cache\poller.stop - touch this file and EVERY poller (orphans included) exits within one interval
#   * cache\poller.pid  - refuse to start a second one; a stale file (dead pid) is ignored, -Force overrides
$stopFile = Join-Path $DshCache 'poller.stop'
$pidFile = Join-Path $DshCache 'poller.pid'
if (Test-Path -LiteralPath $stopFile) { Write-Host ("poller: {0} exists - not starting (delete it to run)" -f $stopFile); exit 0 }
if (Test-Path -LiteralPath $pidFile) {
    $oldPid = 0
    try { $oldPid = [int]([System.IO.File]::ReadAllText($pidFile).Trim()) } catch { }
    $alive = $false
    if ($oldPid -gt 0) { try { $alive = ($null -ne (Get-Process -Id $oldPid -ErrorAction Stop)) } catch { $alive = $false } }
    if ($alive -and -not $Force) { Write-Host ("poller: already running as pid {0} (use -Force to start another)" -f $oldPid); exit 0 }
}
[System.IO.File]::WriteAllText($pidFile, "$PID`n", (New-Object System.Text.UTF8Encoding($false)))

# start from the current truth so the first write is not a false transition
$cur = (& powershell -NoProfile -ExecutionPolicy Bypass -File $side | Select-Object -Last 1)
[System.IO.File]::WriteAllText($OutFile, "$cur`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("poller: start side=$cur interval=${IntervalSec}s file=$OutFile")

while ((Get-Date) -lt $stopAt) {
    Start-Sleep -Milliseconds ([int]($IntervalSec * 1000))
    if (Test-Path -LiteralPath $stopFile) { Write-Host 'poller: stop file seen, exiting'; break }
    $now = (& powershell -NoProfile -ExecutionPolicy Bypass -File $side | Select-Object -Last 1)
    if ($now -ne $cur -and ($now -eq 'mine' -or $now -eq 'player')) {
        $cur = $now
        [System.IO.File]::WriteAllText($OutFile, "$cur`n", (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("poller: {0} -> {1}" -f (Get-Date -Format 'HH:mm:ss'), $cur)
    }
}
try { Remove-Item -LiteralPath $pidFile -Force } catch { }
Write-Host 'poller: stopped'
