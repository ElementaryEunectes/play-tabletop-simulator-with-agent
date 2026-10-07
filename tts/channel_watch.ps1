# channel_watch.ps1 - turn the TTS notebook channel into a file a sentinel can watch.
#
# WHY: the mod notebook ("DSH 对话频道") is the only channel that lets the human talk to
# us WITHOUT leaving Tabletop Simulator. Focus never moves -> the turn watcher keeps
# working too. But a sentinel cannot run Lua, and the save only refreshes every ~5 min,
# so we poll: this script reads the tab LIVE and writes a one-line state file.
#
# Signal design (important): a naive "write the length" file never gives the sentinel a
# no-match -> match edge, because the pattern would stay matched forever. So we keep our
# OWN baseline and write NEW exactly once per change, SAME otherwise. A file sentinel
# with pattern "NEW" then fires exactly once per human message.
#
# ⚠️ 2026-10-07 - THIS SCRIPT NO LONGER SPAWNS ds.ps1.
#   It used to run `powershell -File ds.ps1 -Do tabread` once per tick. That makes ds.ps1 a
#   NESTED child process, and the sandbox kills the network of nested children: our own
#   measurement showed dsbatch.ps1 -> ds.ps1 (two levels) failing wholesale with
#   "ERR TTS unreachable" while one level works. This watcher is started as a background job
#   (already level 1), so ds.ps1 inside it was level 2 => the channel watch was silently dead.
#   It now dot-sources ttslib.ps1 and does the TCP in ITS OWN process, same code as ttsx.ps1.
#
# ASCII only, except comments. Chinese comments require the UTF-8 BOM: run check_ps1.ps1.
param(
    [string]$Ds        = '',
    [string]$OutFile   = '',
    [int]$Minutes      = 120,
    [int]$IntervalMs   = 5000,
    [int]$TailChars    = 200,
    # Must exceed IntervalMs so a single slow poll cannot eat the whole tick budget.
    [int]$TimeoutSec   = 12
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($Ds -eq '') { $Ds = (Join-Path $DshTts 'ds.ps1') }
if ($OutFile -eq '') { $OutFile = (Join-Path $DshCache 'chan.txt') }

. (Join-Path $PSScriptRoot 'ttslib.ps1')

# Live tabread, in-process. Returns @{ err=...; chars=...; tail=... }.
function Read-Tab {
    $env2 = New-TtsEnvelope -Cmd '{"cmd":"tabread"}'
    if ($null -eq $env2) { return @{ err = 'BADENV' } }
    $r = Invoke-Tts -Envelope $env2 -TimeoutSec $TimeoutSec
    if ($r.err) { return @{ err = $r.err } }
    if ($null -eq $r.custom) { return @{ err = 'NOCUSTOM' } }
    $body = [string]$r.custom.body
    $tail = $body
    if ($TailChars -gt 0 -and $tail.Length -gt $TailChars) { $tail = $tail.Substring($tail.Length - $TailChars) }
    return @{ err = $null; chars = [int]$r.custom.chars; tail = $tail }
}

# ⚠️ 2026-10-05 修的一个真 bug：原先只按 `chars` **增长**判 NEW，但**我自己发言会把笔记本裁剪**
# （say.ps1 只保留 ~600 + 新内容）⇒ chars 会掉下来，$lastKey 却停在旧的高位 ⇒ 玩家之后写的话
# 长度没超过旧高位 ⇒ **永远不触发**（玩家 2026-10-05 因此白等了一次）。
# 现在改成**看尾部内容有没有变**：变了就是有新东西（我自己发言也会触发一次，属于可接受的空唤醒）。
$lastKey = ''
$deadline = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $deadline) {
    $tag = 'ERR'
    $len = -1
    $tail = ''
    $res = Read-Tab
    if ($null -eq $res.err) {
        $len = $res.chars
        $tail = ($res.tail -replace "`r", ' ' -replace "`n", ' ')
        $key = if ($tail.Length -gt 160) { $tail.Substring($tail.Length - 160) } else { $tail }
        if ($lastKey -eq '')        { $tag = 'INIT'; $lastKey = $key }
        elseif ($key -ne $lastKey)  { $tag = 'NEW';  $lastKey = $key }
        else                        { $tag = 'SAME' }
    } else {
        # Write the real reason instead of a bare ERR: PORTCLOSED means 39999 refused,
        # which is a different situation from a listener clash or a timeout.
        $tag = 'ERR-' + $res.err
    }
    $line = $tag + ' ' + $len + ' ' + (Get-Date -Format 'HH:mm:ss') + ' | ' + $tail
    try { [System.IO.File]::WriteAllText($OutFile, $line) } catch { }
    Start-Sleep -Milliseconds $IntervalMs
}
try { [System.IO.File]::WriteAllText($OutFile, 'WATCHEND') } catch { }