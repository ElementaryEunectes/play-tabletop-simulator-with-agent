# tts\lib\play.bridge.ps1 - split out of play.ps1 (2026-10-08) so it can be READ on its own.
# play.ps1 dot-sources this: SAME process, no extra PowerShell start-up (0.35 s each). Never spawn it.

function Bridge($Cmd, [int]$TimeoutSec = 15, [switch]$Soft) {
    $env = @{ messageID = 2; customMessage = $Cmd } | ConvertTo-Json -Depth 8 -Compress
    $r = $null
    for ($i = 1; $i -le 3; $i++) {
        $r = Invoke-Tts -Envelope $env -TimeoutSec $TimeoutSec
        if ($r.err -ne 'LISTENERBUSY') { break }
        Start-Sleep -Milliseconds 500
    }
    # -Soft: a cosmetic read (the notebook tail) must not kill the whole command, so it
    # returns $null instead of exiting. Every other call keeps the hard failure.
    if ($r.err) { if ($Soft) { return $null }; Fail (Err-Code $r.err) ("cmd=" + $Cmd.cmd + " (" + $r.err + ")") }
    if ($null -eq $r.custom) { if ($Soft) { return $null }; Fail 'BAD DATA' ("reply from TTS was not JSON (cmd=" + $Cmd.cmd + ")") }
    if ($r.custom.ok -ne $true) {
        if ($Soft) { return $null }
        $e = 'unknown'
        if ($null -ne $r.custom.err) { $e = [string]$r.custom.err }
        Fail 'BAD DATA' ("cmd=" + $Cmd.cmd + " rejected by bridge: " + $e)
    }
    return $r.custom
}

function Ping-Custom { return (Bridge @{ cmd = 'ping' }) }

# Counter read: HP and CP both live in the object's script_state as {"saved_count":N}.
function Get-Counter([string]$Guid, [string]$What) {
    $c = Bridge @{ cmd = 'act'; guid = $Guid; verb = 'getScriptState' }
    $s = ''
    if ($null -ne $c.result) { $s = [string]$c.result }
    if ($s -notmatch 'saved_count"\s*:\s*(-?\d+)') {
        Fail 'BAD DATA' ("$What counter $Guid did not return saved_count (got: " + $s + ")")
    }
    return [int]$Matches[1]
}

# Counter write: setcount does desc + customSet() + script_state, then we READ IT BACK.
function Set-Counter([string]$Guid, [int]$Want, [string]$What) {
    $before = Get-Counter $Guid $What
    $c = Bridge @{ cmd = 'setcount'; guid = $Guid; value = $Want }
    $after = Get-Counter $Guid $What
    if ($after -ne $Want) {
        Fail 'BAD DATA' ("$What write did not stick: wanted $Want, read back $after (was $before, guid $Guid)")
    }
    return @{ before = $before; after = $after }
}

# ------------------------------------------------------------- tiny converters ---
function As-Int([object]$v) {
    if ($null -eq $v) { return $null }
    $s = [string]$v
    if ($s -match '^-?\d+$') { return [int]$s }
    return $null
}

function As-Dict([object]$o) {
    $d = @{}
    if ($null -eq $o) { return $d }
    foreach ($p in $o.PSObject.Properties) { $d[$p.Name] = $p.Value }
    return $d
}

# status / gain may be a plain array, a string, or an object with a "gain" list.
function As-Strings([object]$o) {
    $out = New-Object System.Collections.ArrayList
    if ($null -eq $o) { return @() }
    if ($o -is [string]) { [void]$out.Add([string]$o); return @($out) }
    if ($o.PSObject.Properties.Name -contains 'gain') { return As-Strings $o.gain }
    foreach ($x in @($o)) { if ($null -ne $x) { [void]$out.Add([string]$x) } }
    return @($out)
}

function Has($o, [string]$name) {
    if ($null -eq $o) { return $false }
    return ($o.PSObject.Properties.Name -contains $name)
}

# Safe scalar read for an optional field: returns the value, or '-' when absent/null.
function Text-Of($o, [string]$name) {
    if (-not (Has $o $name)) { return '-' }
    $v = $o.$name
    if ($null -eq $v) { return '-' }
    return [string]$v
}

function Set-Lock([string]$g, [bool]$on) {
    $c = Bridge @{ cmd = 'act'; guid = $g; verb = 'setLock'; value = $on }
    $c = Bridge @{ cmd = 'act'; guid = $g; verb = 'getLock' }
    $now = [string]$c.result
    if ($on -and ($now -notmatch 'true')) { Fail 'BAD DATA' ("lock did not take on $g (getLock=" + $now + ")") }
    if ((-not $on) -and ($now -match 'true')) { Fail 'BAD DATA' ("unlock did not take on $g (getLock=" + $now + ")") }
}
