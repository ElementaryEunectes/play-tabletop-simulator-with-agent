# front_watch.ps1 - keep a one-line file that says whether TTS owns the foreground.
#
# WHY THIS EXISTS
#   A sentinel "command" probe runs in the READ-ONLY sandbox, which is
#   PowerShell ConstrainedLanguage: Add-Type / .NET statics are unavailable, so
#   tts_click.ps1 -Action probe dies there (observed: exit 4294770688, 0 fires).
#   A sentinel "file" probe needs no scripting at all - it just snapshots a file.
#   So we split the job: THIS script (run by us, in workspace-write = FullLanguage,
#   where Add-Type works) polls the foreground and writes the verdict to a file;
#   the file sentinel then watches that file and wakes the agent on the edge.
#
# ASCII only.
param(
    [string]$OutFile   = '',
    [int]$Minutes      = 45,
    [int]$IntervalMs   = 2500,
    [string]$ProbeScript = '',
    [string]$TurnScript  = ''
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($OutFile -eq '') { $OutFile = (Join-Path $DshCache 'front.txt') }
if ($ProbeScript -eq '') { $ProbeScript = (Join-Path $DshTts 'tts_click.ps1') }
if ($TurnScript -eq '') { $TurnScript = (Join-Path $DshTts 'read_turn.ps1') }

$deadline = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $deadline) {
    $state = 'OTHER'
    try {
        $p = & powershell -NoProfile -ExecutionPolicy Bypass -File $ProbeScript -Action probe 2>&1 | Out-String
        if ($p -match 'TTs is foreground : True') { $state = 'TTSFRONT' }
    } catch {
        $state = 'PROBEERR'
    }
    $line = $state
    # While TTS is in front we can ALSO read whose turn the mod thinks it is, straight
    # off the banner's colour swatch (read_turn.ps1). That makes this file the single
    # signal a sentinel needs: "it is Pn's turn AND TTS is visible to us".
    if ($state -eq 'TTSFRONT' -and (Test-Path $TurnScript)) {
        try {
            $t = & powershell -NoProfile -ExecutionPolicy Bypass -File $TurnScript 2>&1 | Out-String
            $m = [regex]::Match($t, 'PLAYER=(\d)')
            # ⚠️ ONLY emit TURN= when the turn actually CHANGED. Writing it every cycle made
            # the file re-match the sentinel's pattern after every focus flicker, so a single
            # turn produced repeated spurious wakeups (observed 3 fires in 80 s on 2026-10-04).
            if ($m.Success) {
                $now = [int]$m.Groups[1].Value
                if ($now -ne $script:lastTurn) {
                    $script:lastTurn = $now
                    $line = $line + ' TURN=P' + $now
                }
            }
        } catch { }
    }
    $line = $line + ' ' + (Get-Date -Format 'HH:mm:ss')
    try { [System.IO.File]::WriteAllText($OutFile, $line) } catch { }
    Start-Sleep -Milliseconds $IntervalMs
}
try { [System.IO.File]::WriteAllText($OutFile, 'WATCHEND') } catch { }