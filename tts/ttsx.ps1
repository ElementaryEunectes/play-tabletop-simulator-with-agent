# ttsx.ps1 - ONE command to talk to Tabletop Simulator. Prints ONLY customMessage.
#
# WHY THIS EXISTS
#   Every TTS round trip used to mean inlining ~20 lines of TCP code inside a tool call
#   (~500 tokens of boilerplate each time, written from scratch). This is that boilerplate,
#   written once, so a call is now: ttsx.ps1 -Cmd '{"cmd":"ping"}'
#
# DESIGN RULES
#   * This script does its OWN TCP. It must NEVER spawn ds.ps1 or any other helper.
#     Reason (measured): the sandbox kills the network of NESTED child processes.
#     dsh -> dsbatch.ps1 -> ds.ps1 is two levels deep and the whole batch fails with
#     "ERR TTS unreachable", while one level (or in-process, like this) works fine.
#   * Output is ONLY the customMessage segment, one line, compressed JSON. Nothing else.
#     No banner, no "ok", no elapsed time - the caller pays for every character.
#   * Reply selection: read until messageID == 4. TTS also pushes unrelated events to
#     39998 (messageID 6 = autosave, 5 = load). Taking the FIRST packet that arrives is
#     what made old runs look like "no reply from TTS". Non-4 IDs are counted and dropped.
#   * "TTS PORT CLOSED" means exactly that: 39999 refused. It does NOT mean "TTS is not
#     running" - the sandbox can kill the network of a nested child while TTS is fine.
#
# USAGE
#   ttsx.ps1 -Cmd '{"cmd":"ping"}'
#   ttsx.ps1 -Exec <guid> -Lua 'return 1+1'
#   ttsx.ps1 -Cmd '{"cmd":"ping"}' -TimeoutSec 20
#
# EXIT CODES
#   0 = reply printed   2 = TTS PORT CLOSED   3 = listener busy after retries   4 = NO REPLY
param(
    [string]$Cmd = '',
    [string]$Exec = '',
    [string]$Lua = '',
    [int]$TimeoutSec = 8,
    [int]$Retries = 3,
    # Test-only: point the outbound side somewhere else so the JSON/arg path can be
    # exercised while TTS is closed (a bad -Cmd must never be reported as a port fault,
    # and that is worth being able to prove without a live game).
    [int]$TtsPort = 39999
)

$ErrorActionPreference = 'Continue'

# All the socket code lives in ttslib.ps1 so this script, channel_watch.ps1 and any inline
# snippet cannot drift apart. Dot-sourcing keeps it IN THIS PROCESS - which is the whole
# point: the sandbox kills the network of nested child processes, so we never spawn a helper.
. (Join-Path $PSScriptRoot 'ttslib.ps1')

# ------------------------------------------------------------------ payload ---
# -Cmd    : a bare command object, wrapped here into {messageID:2, customMessage:...}.
# -Exec/-Lua : build the messageID 3 envelope {messageID:3, guid:<g>, script:<lua>}.
# JSON is built by ConvertTo-Json so a multi-line Lua body gets escaped correctly;
# hand-rolled string concatenation is what breaks on multi-line Lua.
if ($Exec -ne '' -or $Lua -ne '') {
    if ($Exec -eq '' -or $Lua -eq '') { Write-Host 'ERR need both -Exec and -Lua'; exit 5 }
    $envelope = New-TtsExecEnvelope -Guid $Exec -Lua $Lua
} elseif ($Cmd -ne '') {
    # New-TtsEnvelope also repairs the quote-eaten form produced by
    # `powershell -File ttsx.ps1 -Cmd '{"cmd":"ping"}'` (PowerShell strips the inner quotes,
    # so $Cmd arrives as the bare word {cmd:ping}). A malformed -Cmd must NEVER fall through
    # to the port logic: that is how a JSON typo once got reported as "TTS PORT CLOSED",
    # sending the next reader after a TTS problem that did not exist.
    $envelope = New-TtsEnvelope -Cmd $Cmd
    if ($null -eq $envelope) { Write-Host 'ERR bad -Cmd JSON (bare-key repair tried, still invalid)'; exit 5 }
} else {
    Write-Host 'ERR nothing to send: use -Cmd or -Exec/-Lua'
    exit 5
}

# ------------------------------------------------------------------ output ---
$r = Invoke-Tts -Envelope $envelope -TimeoutSec $TimeoutSec -Retries $Retries -TtsPort $TtsPort

# One-line verdicts, and each fault gets its OWN wording. "TTS PORT CLOSED" means exactly
# that - 39999 refused - and is never used for an input, listener or timeout problem.
switch ($r.err) {
    'PORTCLOSED'   { Write-Host 'TTS PORT CLOSED'; exit 2 }   # NOT a verdict on the TTS process
    'LISTENERBUSY' { Write-Host "ERR listener busy on 39998 (retried $Retries)"; exit 3 }
    'NOREPLY'      { Write-Host "NO REPLY (${TimeoutSec}s, skipped $($r.skipped))"; exit 4 }
}

# Print ONLY customMessage, compressed, one line. If a messageID 4 reply has no
# customMessage (should not happen) fall back to the raw packet so nothing is hidden.
if ($null -eq $r.custom) { Write-Host $r.raw; exit 0 }
Write-Host ($r.custom | ConvertTo-Json -Depth 10 -Compress)
exit 0
