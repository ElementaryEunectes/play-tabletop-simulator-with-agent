# play.ps1 - GENERIC ENTRY POINT: dispatch to the current game's control layer.
#
# WHY THIS FILE EXISTS (2026-10-09, the layer split)
#   The repository ships GENERIC PRIMITIVES only: everything in tts\ must be true for ANY TTS mod.
#   A per-round console is NOT generic - it carries one game's seats, counters, dice trays and skill
#   table. That console now lives with its game, at local\games\<game>\control\play.ps1 (gitignored),
#   and this file is the stable entry point that finds and runs it.
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

if ($DshGame -eq '') {
    return (Fail 'NO PART' 'no current game: set the GAME= line in local\games\_current.md')
}
if ($DshGameControl -eq '' -or -not (Test-Path -LiteralPath $DshGameControl)) {
    return (Fail 'NO PART' ("this game has no control layer yet: " + $DshGameControl + "  <- see tts\docs\BOOTSTRAP.md section 2"))
}

& $DshGameControl @args
# Carry the control layer's exit code out. `exit` inside a script FILE is caught by that file's own
# boundary, so its code lands in $LASTEXITCODE - but any successful line afterwards resets that to 0.
# Capture it on the very next line; do NOT read $LASTEXITCODE later and expect the same value.
$code = $LASTEXITCODE
return $code
