# play.ps1 - Dice Throne: ONE COMMAND PER ROUND.
#
# WHY THIS EXISTS
#   Mid-game the main agent's context fills up, so every turn used to cost either a
#   sub-agent spawn or a re-read of the rulebook. This script ends that: it carries the
#   per-game constants (counters, dice, symbols, skill table) and the TTS transport in
#   one process, and prints at most a few lines per command.
#
# USAGE (ASCII only on the command line; Chinese lives in the data file)
#   play.ps1 turn                       # ONE call per turn: board + my dice (read-only) + notebook tail
#   play.ps1 status
#   play.ps1 income  -Seat moon
#   play.ps1 roll    -Seat moon [-Roll] [-NoRoll] [-Lock 1,3] [-Tries 1]
#   play.ps1 attack  -Seat moon -Ability '<name>' [-Apply] [-Damage N] [-Idx K]
#   play.ps1 defense -Seat scar [-Roll] [-NoRoll] [-Apply -Incoming N] [-Damage N]
#   play.ps1 say     -TextFile <utf8 file>
#
# ERROR CODES (each one is a DIFFERENT fault and must never be blurred)
#   NO PART  : the data file cache\dicethrone_rules.json is missing or unreadable
#   BAD DATA : a counter / a reply / the data file could not be parsed. Hard stop.
#   NO PORT  : 127.0.0.1:39999 refused (and 39998 free) -> TTS is not listening
#   NO REPLY : connected, but no messageID 4 came back in time
#   BUSY     : 127.0.0.1:39998 is held by another listener (channel_watch) -> retry
#   LOOKUP   : the data table has no such ability / no matcher for that seat
#
# IRON RULE: every write to HP/CP is read back and the read-back is printed. A write
#   whose read-back disagrees is reported as BAD DATA, never smoothed over.
# GUARDRAILS: roll/defense are READ-ONLY unless -Roll is passed (there is no rolling default);
#   -Apply is the ONLY writer and it accepts -WhatIf, which prints the exact HP change and
#   touches nothing. Use -WhatIf whenever the damage number is still under argument.
#
# ASCII only outside comments and the few Chinese strings that ARE the game's own names.
# Requires the UTF-8 BOM: run tts\check_ps1.ps1 after any edit.

# SupportsShouldProcess is what makes -WhatIf bindable. The write checks $WhatIfPreference
# directly instead of calling ShouldProcess, so -Confirm can never block a non-interactive run.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [ValidateSet('turn', 'status', 'income', 'roll', 'attack', 'defense', 'say')]
    [string]$Action = 'status',

    [ValidateSet('moon', 'scar')]
    [string]$Seat = 'moon',

    [string]$Ability = '',

    [int[]]$Lock = @(),
    [int]$Tries = 0,
    [switch]$Roll,
    [switch]$NoRoll,
    [switch]$Apply,
    [int]$Incoming = 0,
    [int]$Damage = -1,
    [int]$Idx = -1,
    [int]$Poll = 25,
    [string]$TextFile = '',
    [string]$RulesFile = '',
    [string]$TtsLib = '',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ($RulesFile -eq '') { $RulesFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'cache\dicethrone_rules.json' }
if ($TtsLib -eq '') { $TtsLib = Join-Path $PSScriptRoot 'ttslib.ps1' }

# ------------------------------------------------------------------ failures -----
# Every exit says WHY in one line, and never invents a value.
function Fail([string]$code, [string]$msg) {
    Write-Host ("{0} {1}" -f $code, $msg)
    exit 1
}

# ------------------------------------------------------------------ plumbing -----
if (-not (Test-Path -LiteralPath $TtsLib)) { Fail 'NO PART' ("ttslib.ps1 not found at " + $TtsLib) }
. $TtsLib

if (-not (Test-Path -LiteralPath $RulesFile)) { Fail 'NO PART' ("rules file not found: " + $RulesFile) }
$Raw = [System.IO.File]::ReadAllText($RulesFile, [System.Text.Encoding]::UTF8)
$Rules = $null
try { $Rules = $Raw | ConvertFrom-Json } catch { Fail 'BAD DATA' ("rules file is not valid JSON: " + $_.Exception.Message) }

# Invoke-Tts error strings -> the four codes this project distinguishes.
function Err-Code([string]$e) {
    switch ($e) {
        'LISTENERBUSY' { return 'BUSY' }      # 39998 held by a watcher: retry, do not alarm
        'PORTCLOSED' { return 'NO PORT' }     # 39999 refused
        'NOREPLY' { return 'NO REPLY' }
        default { return 'BAD DATA' }
    }
}

# One bridge command object -> the customMessage object, or die with the right code.

# --- implementation modules (dot-sourced: same process, no child PowerShell) ---
. "$PSScriptRoot\lib\play.bridge.ps1"
. "$PSScriptRoot\lib\play.dice.ps1"
. "$PSScriptRoot\lib\play.rules.ps1"
. "$PSScriptRoot\lib\play.verbs.ps1"

switch ($Action) {
    'turn' { Cmd-Turn }
    'status' { Cmd-Status }
    'income' { Cmd-Income }
    'roll' { Cmd-Roll }
    'attack' { if ($Ability -eq '') { Fail 'LOOKUP' 'attack needs -Ability <name from cache\dicethrone_rules.json>' } ; Cmd-Attack }
    'defense' { Cmd-Defense }
    'say' { Cmd-Say }
}
if ($SelfTest) { Cmd-SelfTest }
