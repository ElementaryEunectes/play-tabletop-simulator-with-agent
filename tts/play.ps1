# play.ps1 - GENERIC ENTRY POINT: dispatch to the current game's control layer.
#
# WHY THIS FILE EXISTS (2026-10-09, the layer split)
#   The repository ships GENERIC PRIMITIVES only: everything in tts\ must be true for ANY TTS mod.
#   A per-round console is NOT generic - it carries one game's seats, counters, dice trays and skill
#   table. That console now lives with its game, at local\games\<game>\control\play.ps1 (gitignored),
#   and this file is the stable entry point that finds and runs it.
#
# ⭐ AND IT MUST NOT BE USELESS WITHOUT ONE (2026-10-11). Measured: the second mod we validated never
#   got a control layer, so EVERY command here replied "NO PART" - including `status`. That is the
#   first command a stranger runs, so the generic entry point now answers `status` (and a bare call)
#   by itself, with facts that hold for any mod: is the bridge up, how many objects, who is seated,
#   and whose turn it is if this game has a turn calibration. Game-specific verbs still need the
#   control layer, and say so.
#
# THE CONTRACT (what a trained control layer must provide)
#   1. File: local\games\<game>\control\play.ps1   (path resolved by tts\config.ps1 as $DshGameControl)
#   2. It must dot-source the generic transport from $DshLibBridge (never a hard-coded repo path).
#   3. Its param() block carries the game's own verbs and options; whatever the user passes here is
#      forwarded verbatim. Common shape: -Action (<verb>) -Seat (<seat>) [-Apply/-WhatIf/-Roll]...
#   4. Read-only by default for anything that would change the table; writes behind an explicit
#      switch, and every write reads its value back before reporting success.
#   Bootstrapping a new game: tts\docs\BOOTSTRAP.md section 2. Ledger of what is proven generic:
#   tts\docs\VALIDATION.md.
#
# ERROR CODES (same meaning as the control layers use)
#   NO PART : no current game, or its control layer is missing (see GAME= in local\games\_current.md)
#
# ASCII only, so a lost UTF-8 BOM cannot mangle it.
# No param() block on purpose: this file must forward the caller's arguments EXACTLY, and $args
# does that in order (verified under Set-StrictMode-free script scope, PowerShell 5.1). A
# ValueFromRemainingArguments parameter was tried first and is WRONG here - it swallows a positional
# verb like `status` before the control layer can bind it to its own -Action parameter.
$ErrorActionPreference = 'Stop'
$DshTtsDir = $PSScriptRoot          # exported on purpose: a control layer finds tts\config.ps1 and
                                    # tts\lib\bridge.ps1 through this, never through a repo path
. (Join-Path $PSScriptRoot 'config.ps1')

function Fail([string]$code, [string]$msg) {
    Write-Host ("{0} {1}" -f $code, $msg)
    return 1
}

# ------------------------------------------------------------------ generic status
# Works for ANY mod with a running bridge: no control layer, no rules file, no schema.
# Runs in-process (ttslib + bridge) so it needs no child PowerShell and stays fast.
# -Soft on every call: a missing optional read must not abort the whole report.
# Bridge() would call Fail/Err-Code on a hard error, but -Soft returns $null first, so only Fail
# needs to exist here (it does, above).
function Show-GenericStatus {
    . $DshLibTtslib
    . $DshLibBridge

    $p = Bridge @{ cmd = 'ping' } -Soft
    if ($null -eq $p) {
        Write-Host 'BRIDGE DOWN - no reply from TTS on the editor API (is the game running and the save loaded?)'
        Write-Host ("game=" + $DshGame + "  control layer: " + $(if ($DshGameControl -ne '') { $DshGameControl } else { '(none)' }))
        return 1
    }
    Write-Host ("bridge={0}  objects={1}  loads={2}" -f (Text-Of $p 'v'), (Text-Of $p 'objects'), (Text-Of $p 'loads'))

    $pl = Bridge @{ cmd = 'players' } -Soft
    if ($null -ne $pl) {
        Write-Host ("players=" + (Text-Of $pl 'count'))
        $seats = Text-Of $pl 'seats'
        if ($seats -ne '-' -and $seats -ne '') {
            try { foreach ($s in ($seats | ConvertFrom-Json)) { Write-Host ("  " + $s) } } catch { Write-Host ("  " + $seats) }
        }
    }

    # whose turn, when this game has been calibrated (cache\<game>_turn.json + a tracker on the table).
    # The guid comes FROM that file, so the piece reported here is the piece the calibration names and
    # tr.ps1 moves; the bridge's built-in constant is only a fallback (2026-10-11).
    $ttArg = @{ cmd = 'turn_tracker' }
    if ($DshCache -ne '' -and $DshGame -ne '') {
        $calib = Join-Path $DshCache ($DshGame + '_turn.json')
        if (Test-Path -LiteralPath $calib) {
            try { $ttArg.guid = [string](([System.IO.File]::ReadAllText($calib, [System.Text.Encoding]::UTF8) | ConvertFrom-Json).tracker) } catch { }
        }
    }
    $tt = Bridge $ttArg -Soft
    if ($null -ne $tt -and (Text-Of $tt 'side') -ne '-') {
        Write-Host ("turn=" + (Text-Of $tt 'side') + "  (position z=" + (Text-Of $tt 'z') + ", guid " + (Text-Of $tt 'guid') + ")")
    } else {
        Write-Host 'turn=(not calibrated for this game - see tts\tools\turn_calib.ps1)'
    }

    if ($DshGameControl -eq '' -or -not (Test-Path -LiteralPath $DshGameControl)) {
        Write-Host ''
        Write-Host 'NOTE: this game has no control layer, so only the generic status above is available.'
        Write-Host ('      game-specific verbs need ' + $DshGameControl + '  <- tts\docs\BOOTSTRAP.md section 2')
    }
    return 0
}

$verb = ''
if ($args.Count -gt 0) { $verb = [string]$args[0] }

if ($DshGame -eq '') {
    return (Fail 'NO PART' 'no current game: set the GAME= line in local\games\_current.md')
}

$hasControl = ($DshGameControl -ne '') -and (Test-Path -LiteralPath $DshGameControl)
if (-not $hasControl -and ($verb -eq '' -or $verb -eq 'status')) {
    return (Show-GenericStatus)
}
if (-not $hasControl) {
    return (Fail 'NO PART' ("this game has no control layer yet, so '" + $verb + "' is unavailable: " + $DshGameControl + "  <- see tts\docs\BOOTSTRAP.md section 2 (try: play.ps1 status)"))
}

& $DshGameControl @args
# Carry the control layer's exit code out. `exit` inside a script FILE is caught by that file's own
# boundary, so its code lands in $LASTEXITCODE - but any successful line afterwards resets that to 0.
# Capture it on the very next line; do NOT read $LASTEXITCODE later and expect the same value.
$code = $LASTEXITCODE
return $code
