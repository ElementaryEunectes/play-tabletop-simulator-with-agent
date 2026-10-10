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

# start from the current truth so the first write is not a false transition
$cur = (& powershell -NoProfile -ExecutionPolicy Bypass -File $side | Select-Object -Last 1)
[System.IO.File]::WriteAllText($OutFile, "$cur`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("poller: start side=$cur interval=${IntervalSec}s file=$OutFile")

while ((Get-Date) -lt $stopAt) {
    Start-Sleep -Milliseconds ([int]($IntervalSec * 1000))
    $now = (& powershell -NoProfile -ExecutionPolicy Bypass -File $side | Select-Object -Last 1)
    if ($now -ne $cur -and ($now -eq 'mine' -or $now -eq 'player')) {
        $cur = $now
        [System.IO.File]::WriteAllText($OutFile, "$cur`n", (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ("poller: {0} -> {1}" -f (Get-Date -Format 'HH:mm:ss'), $cur)
    }
}
Write-Host 'poller: stopped'
