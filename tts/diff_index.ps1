# diff_index.ps1 - "what did the player just do?" by diffing two object-index snapshots.
#
# WHY THIS EXISTS
#   TTS gives us no event stream. We cannot subscribe to "the player clicked the quick
#   action on card X". All we ever see is STATE. So the way to read somebody else's
#   move is:
#       1. freeze a baseline of the whole table   (diff_index.ps1 -Snapshot)
#       2. let them act
#       3. diff                                     (diff_index.ps1)
#   Every action that leaves a footprint shows up -- AS LONG AS THE SNAPSHOT CARRIES IT.
#   A LIVE snapshot does not carry everything, and that decides what this script can say:
#     added / removed / moved / flipped           always available (guid set, x/z, rotZ)
#     reparented (into or out of a container)     needs `parent`
#     state (counters / LuaScriptState / GMNotes) needs `gm` / `ss`
#   tts\live_index.ps1 hard-codes parent/gm/ss as EMPTY (see its LIMITS block), so on a real
#   table this script reports FOUR of the six classes; the other two need obj_index.ps1, which
#   parses the autosave - correct, but TTS writes that only every ~5 minutes.
#   => when the snapshots carry no parent/gm/ss values, this script PRINTS A NOTE, so that
#      "reparented=0 state=0" is never read as "nothing like that happened".
#
# WHAT IT CANNOT SEE
#   - pure click events with no state change (a button that only prints, a chat line)
#   - transient moves: something moved and moved back between the two snapshots
#   - WHICH of a card's two effects was chosen, unless that choice changed some state
#   => when it matters, still have the player say one line in the notebook. The diff
#      is a safety net, not a substitute for the player's own report.
#
# USAGE
#   powershell -File diff_index.ps1 -Snapshot      # freeze the current table as baseline
#   ... (player acts) ...
#   powershell -File diff_index.ps1                # report everything that changed
param(
    [string]$Before  = '',
    [string]$After   = '',
    [string]$LiveIndex = '',
    [double]$MoveTol = 0.30,     # world units; below this it is physics jitter, not a move
    [double]$RotTol  = 25.0,     # degrees
    [int]$MaxRows    = 40,
    [switch]$Snapshot
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($LiveIndex -eq '') { $LiveIndex = (Join-Path $DshTts 'live_index.ps1') }
# Backfills AFTER config.ps1 -- restored 2026-10-08. Without them BOTH modes died, because
# Test-Path / Copy-Item were handed an empty path ("ERR missing " / "ERR no live index at ").
# After  = the live snapshot that diff_hidden.ps1 also reads;
# Before = the frozen baseline this script writes with -Snapshot.
if ($After  -eq '') { $After  = (Join-Path $DshCache 'live_index.csv') }
if ($Before -eq '') { $Before = (Join-Path $DshCache 'baseline.csv') }

$ErrorActionPreference = 'Stop'

if ($Snapshot) {
    & $LiveIndex -Out $After
    if (-not (Test-Path -LiteralPath $After)) { Write-Host ("ERR no live index at {0}" -f $After); exit 1 }
    Copy-Item -LiteralPath $After -Destination $Before -Force
    $rows = @(Import-Csv -LiteralPath $Before)
    Write-Host ("SNAPSHOT  baseline <- LIVE {0}   ({1} objects)" -f (Split-Path $Before -Leaf), $rows.Count)
    Write-Host "现在让玩家行动，之后不带参数再跑一次本脚本即可看到差异。"
    exit 0
}

& $LiveIndex -Out $After
foreach ($p in @($Before, $After)) { if (-not (Test-Path -LiteralPath $p)) { Write-Host ("ERR missing {0}" -f $p); exit 1 } }
$old = @{}; foreach ($r in Import-Csv -LiteralPath $Before) { $old[$r.guid] = $r }
$new = @{}; foreach ($r in Import-Csv -LiteralPath $After)  { $new[$r.guid] = $r }
# Two of the six classes live in columns a live snapshot leaves empty. Say so out loud instead
# of printing a zero that reads like "the player did not do that".
function Test-AnyValue($rows, [string[]]$cols) {
    foreach ($r in $rows) { foreach ($c in $cols) { $p = $r.PSObject.Properties[$c]; if ($p -and "$($p.Value)" -ne '') { return $true } } }
    return $false
}
$blind = @()
if (-not (Test-AnyValue (@($old.Values) + @($new.Values)) @('parent')))    { $blind += 'reparented' }
if (-not (Test-AnyValue (@($old.Values) + @($new.Values)) @('gm', 'ss')))  { $blind += 'state' }
if ($blind.Count -gt 0) {
    Write-Host ("NOTE  snapshot carries no parent/gm/ss values -> NOT reported this run: {0}  (live mode sees 4 of 6 classes; for container/state changes use obj_index.ps1, ~5 min autosave lag)" -f ($blind -join ' + '))
}
Write-Host ("baseline {0} objs   now {1} objs" -f $old.Count, $new.Count)

$added = @(); $removed = @(); $moved = @(); $flipped = @(); $reparented = @(); $stateChanged = @(); $nickChanged = @()
foreach ($g in $new.Keys) {
    if (-not $old.ContainsKey($g)) { $added += $new[$g]; continue }
    $o = $old[$g]; $n = $new[$g]
    $dx = [double]$n.x - [double]$o.x; $dz = [double]$n.z - [double]$o.z
    $dist = [math]::Sqrt(($dx * $dx) + ($dz * $dz))
    if ($dist -gt $MoveTol) {
        $moved += [pscustomobject]@{ guid = $g; name = $n.name; nick = $n.nick
            from = ("({0:N2},{1:N2})" -f [double]$o.x, [double]$o.z)
            to   = ("({0:N2},{1:N2})" -f [double]$n.x, [double]$n.z)
            d    = [math]::Round($dist, 2) }
    }
    $drz = [math]::Abs([double]$n.rotZ - [double]$o.rotZ)
    if ($drz -gt $RotTol -and [math]::Abs($drz - 360) -gt $RotTol) {
        $side = '?'
        if ([double]$o.rotZ -lt 90 -and [double]$n.rotZ -gt 90) { $side = '面朝上 -> 面朝下' }
        if ([double]$o.rotZ -gt 90 -and [double]$n.rotZ -lt 90) { $side = '面朝下 -> 面朝上 (翻开!)' }
        $flipped += [pscustomobject]@{ guid = $g; name = $n.name; nick = $n.nick
            rotZ = ("{0:N0} -> {1:N0}" -f [double]$o.rotZ, [double]$n.rotZ); note = $side }
    }
    if ("$($o.parent)" -ne "$($n.parent)") { $reparented += [pscustomobject]@{ guid = $g; name = $n.name; nick = $n.nick; from = $o.parent; to = $n.parent } }
    if ("$($o.gm)" -ne "$($n.gm)" -or "$($o.ss)" -ne "$($n.ss)") {
        $stateChanged += [pscustomobject]@{ guid = $g; name = $n.name; nick = $n.nick; gm = ("'{0}' -> '{1}'" -f $o.gm, $n.gm) }
    }
    # NICKNAME: the turn token writes its counter here ("DSH-TURN <n>"). It is the one channel that
    # needs no help from the mod's own turn machine - and it was simply never compared before.
    if ("$($o.nick)" -ne "$($n.nick)") {
        $nickChanged += [pscustomobject]@{ guid = $g; name = $n.name; was = $o.nick; now = $n.nick }
    }
}
foreach ($g in $old.Keys) { if (-not $new.ContainsKey($g)) { $removed += $old[$g] } }

function Show($title, $list, $cols) {
    if (@($list).Count -eq 0) { return }
    Write-Host ("`n=== {0} : {1} ===" -f $title, @($list).Count)
    $n = 0
    foreach ($r in $list) {
        if ($n -ge $MaxRows) { Write-Host ("  ... (+{0} more)" -f (@($list).Count - $MaxRows)); break }
        $parts = @()
        foreach ($c in $cols) { $parts += ("{0}={1}" -f $c, $r.$c) }
        Write-Host ("  {0}  {1}" -f $r.guid, ($parts -join '  '))
        $n++
    }
}
Show 'ADDED (新建)'      $added         @('name', 'nick', 'x', 'z')
Show 'REMOVED (消失)'    $removed       @('name', 'nick', 'x', 'z')
Show 'MOVED (移动)'      $moved         @('name', 'nick', 'from', 'to', 'd')
Show 'FLIPPED (翻面)'    $flipped       @('name', 'nick', 'rotZ', 'note')
Show 'REPARENTED (换容器)' $reparented  @('name', 'nick', 'from', 'to')
Show 'STATE (数值/脚本状态)' $stateChanged @('name', 'nick', 'gm')
Show 'NICK (昵称变化)'     $nickChanged   @('name', 'was', 'now')

Write-Host ("`nSUMMARY  added={0} removed={1} moved={2} flipped={3} reparented={4} state={5} nick={6}" -f `
    @($added).Count, @($removed).Count, @($moved).Count, @($flipped).Count, @($reparented).Count, @($stateChanged).Count, @($nickChanged).Count)
