# live_smoke.ps1 - read-only live check of the bridge: which commands actually answer on THIS table.
#
# WHY: the offline gates prove the bridge loads and its Lua compiles. They cannot prove a command works
# against a running game - that has bitten this project repeatedly (commands registered but names nil; a
# verb that took the whole game down). So after every bake + reload, run this: it sends only READ-ONLY
# commands and prints PASS/FAIL per command, so a broken subset is visible in one shot instead of being
# found mid-round.
#
# ⛔ Deliberately excluded: call / callx (measured twice to make TTS unreachable), spawn:type (refused by
# the bridge on purpose), run (needs eval, absent in this sandbox).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\live_smoke.ps1
param(
    [string]$Root = '',
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'tts\config.ps1')
. (Join-Path $Root 'tts\ttslib.ps1')
. (Join-Path $Root 'tts\lib\bridge.ps1')
if (-not (Get-Command Fail -ErrorAction SilentlyContinue)) { function Fail($c, $m) { throw ("$c $m") } }
if (-not (Get-Command Err-Code -ErrorAction SilentlyContinue)) { function Err-Code($e) { return 'BAD DATA' } }

function Send($cmd, [int]$TimeoutSec = 15) {
    $env2 = @{ messageID = 2; customMessage = $cmd } | ConvertTo-Json -Depth 8 -Compress
    return (Invoke-Tts -Envelope $env2 -TimeoutSec $TimeoutSec)
}

# A real guid first, BEFORE the case list is built: several commands need one, and PowerShell evaluates
# $someGuid at array-construction time - building the list first is how the earlier version sent an empty
# guid and reported four false failures.
$someGuid = ''
$idx0 = Send @{ cmd = 'index'; limit = 5 } 20
if ($null -eq $idx0.err -and $null -ne $idx0.custom -and [string]$idx0.custom.ok -eq 'True') {
    try {
        $items = $idx0.custom.items
        if ($items -is [string]) { $items = $items | ConvertFrom-Json }
        $first = @($items) | Select-Object -First 1
        if ($null -ne $first) { $someGuid = [string]$first.guid }
    } catch { }
}
if ($someGuid -eq '') { Write-Host 'WARN no guid available - guid-taking commands will be SKIPped' }

$tests = @(
    @{ n = 'ping'; c = @{ cmd = 'ping' }; want = 'v' },
    @{ n = 'count'; c = @{ cmd = 'count' } },
    @{ n = 'index'; c = @{ cmd = 'index'; limit = 5 } },
    @{ n = 'all'; c = @{ cmd = 'all'; limit = 5 } },
    @{ n = 'find'; c = @{ cmd = 'find'; filter = 'a'; limit = 3 } },
    @{ n = 'players'; c = @{ cmd = 'players' }; want = 'count' },
    @{ n = 'diag'; c = @{ cmd = 'diag' } },
    @{ n = 'selftest'; c = @{ cmd = 'selftest' } },
    @{ n = 'env'; c = @{ cmd = 'env' } },
    @{ n = 'turn_tracker'; c = @{ cmd = 'turn_tracker' } },
    @{ n = 'hand'; c = @{ cmd = 'hand'; player = 'Brown'; action = 'get' } },
    @{ n = 'noteread'; c = @{ cmd = 'noteread' } },
    @{ n = 'tablist'; c = @{ cmd = 'tablist' } },
    @{ n = 'whose'; c = @{ cmd = 'whose'; guids = $someGuid }; needsGuid = $true },
    @{ n = 'read'; c = @{ cmd = 'read'; guid = $someGuid }; needsGuid = $true },
    @{ n = 'probe'; c = @{ cmd = 'probe'; guid = $someGuid }; needsGuid = $true },
    @{ n = 'meta'; c = @{ cmd = 'meta'; guid = $someGuid }; needsGuid = $true }
)

$pass = 0; $fail = 0
foreach ($t in $tests) {
    if ($t.needsGuid -and $someGuid -eq '') { Write-Host ("SKIP  {0,-14} (no guid on the table)" -f $t.n); continue }
    # Via Invoke-Tts, not Bridge: Bridge's -Soft turns an ok=false REPLY into $null, which reads as "no
    # reply" and hides the bridge's own error text.
    $r = Send $t.c
    if ($r.err) { Write-Host ("FAIL  {0,-14} transport: {1}" -f $t.n, $r.err); $fail++; continue }
    if ($null -eq $r.custom) { Write-Host ("FAIL  {0,-14} reply was not JSON" -f $t.n); $fail++; continue }
    if ([string]$r.custom.ok -ne 'True') {
        $e = '?'; if ($null -ne $r.custom.err) { $e = [string]$r.custom.err }
        Write-Host ("FAIL  {0,-14} ok=false err={1}" -f $t.n, $e); $fail++; continue
    }
    if ($t.want -and ($null -eq $r.custom.($t.want))) {
        Write-Host ("FAIL  {0,-14} ok but no '{1}' field" -f $t.n, $t.want); $fail++; continue
    }
    if (-not $Quiet) {
        $extra = ''
        if ($t.n -eq 'ping') { $extra = 'v=' + [string]$r.custom.v + ' objects=' + [string]$r.custom.objects }
        if ($t.n -eq 'turn_tracker') { $extra = 'side=' + [string]$r.custom.side + ' z=' + [string]$r.custom.z }
        if ($t.n -eq 'players') { $extra = 'count=' + [string]$r.custom.count }
        Write-Host ("PASS  {0,-14} {1}" -f $t.n, $extra)
    }
    $pass++
}
Write-Host ("smoke: pass={0} fail={1}" -f $pass, $fail)
if ($fail -gt 0) { return 1 }
return 0
