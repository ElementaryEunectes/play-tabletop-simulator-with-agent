# ds.ps1 - the single TTS entry point, built for minimum output tokens.
#
# WHY THIS EXISTS
#   The previous path (write payload.json -> run ask.ps1 -> dump the whole reply)
#   printed indented JSON, and tabread returned the entire 1807-char notebook body
#   every time. That is hundreds of tokens per call, most of it noise. This script
#   prints a ONE-LINE summary instead, and only echoes a field when asked.
#
# USAGE
#   ds.ps1 -Do ping
#   ds.ps1 -Do tabread                     # one line: chars + tail
#   ds.ps1 -Do tabread -Tail 300           # also the last 300 chars of the body
#   ds.ps1 -Do 'tabwrite:MESSAGE TEXT'     # write the dialogue tab
#   ds.ps1 -Do 'notepush:MESSAGE'          # write the on-screen notes area
#   ds.ps1 -Do 'act:<guid>:<verb>[:value]'
#   ds.ps1 -Raw -Json '<full envelope>'    # escape hatch, prints raw reply
#
# DESIGN RULES THAT SAVE TOKENS
#   * one line of output in the normal case
#   * never re-print a body that was just sent (only its length is echoed)
#   * broadcast events (TTS messageID 6 = save, 5 = load) are skipped, not printed
#   * no indented JSON, ever
param(
    [string]$Do = 'ping',
    [int]$Tail = 0,                 # how many trailing chars of a body to echo
    [int]$TimeoutSec = 25,
    [switch]$Raw,
    [string]$Json = '',
    # Body text read from a UTF-8 file. Use this for anything long or non-ASCII:
    # message text on the command line is fragile, and passing it through -Do
    # risks mangling Chinese.
    [string]$TextFile = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'
$TTS = 39999
$ED = 39998

# ---------------------------------------------------------------- transport ---
# TTS listens on 39999 for our commands and connects back to 39998 with the reply.
# It ALSO pushes unrelated events to 39998 (messageID 6 on every autosave), so a
# reply must be identified by messageID 4 - taking the first message that arrives
# is what made earlier runs look like "no reply from TTS".
. "$PSScriptRoot\ttslib.ps1"   # the ONE TCP transport (see ttslib.ps1)

function Send-TTS([string]$payload, [int]$timeout) {
    # Transport lives in ttslib.ps1, dot-sourced just above. This used to be a second
    # implementation of the same ~30 lines -- same 15 ms poll, same "identify the reply by
    # messageID 4" rule, same keep-the-socket-open reasoning -- but WITHOUT the busy-retry.
    # The three error strings are what callers already match on, so they stay verbatim.
    $r = Invoke-Tts -Envelope $payload -TimeoutSec $timeout -TtsPort $TTS
    switch ($r.err) {
        'LISTENERBUSY' { return @{ err = "listener busy on $ED" } }
        'PORTCLOSED'   { return @{ err = "TTS unreachable" } }
        'NOREPLY'      { return @{ err = "no reply in ${timeout}s (skipped $($r.skipped) broadcasts)" } }
    }
    return @{ ok = $true; json = $r.raw; skipped = $r.skipped }
}

# Compact one-line rendering of a TTS reply. The reply is always
# { customMessage = {...}, messageID = 4 }; the interesting part is customMessage.
function Fmt($obj) {
    if ($null -eq $obj) { return 'null' }
    if ($obj -is [string]) { return $obj }
    $parts = @()
    foreach ($p in $obj.PSObject.Properties) {
        $v = $p.Value
        if ($null -eq $v) { continue }
        if ($v -is [string]) {
            # long strings become a length marker; the caller asks for content explicitly
            if ($v.Length -gt 90) { $parts += ("{0}=<{1}c>" -f $p.Name, $v.Length) }
            else { $parts += ("{0}={1}" -f $p.Name, $v) }
        } elseif ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) {
            $parts += ("{0}=[{1}]" -f $p.Name, (@($v).Count))
        } else {
            $parts += ("{0}={1}" -f $p.Name, $v)
        }
    }
    return ($parts -join ' ')
}

# ---------------------------------------------------------------- build call --
$cm = $null
switch -Regex ($Do) {
    '^ping$'        { $cm = @{ cmd = 'ping' } }
    '^tabread$'     { $cm = @{ cmd = 'tabread' } }
    '^tablist$'     { $cm = @{ cmd = 'tablist' } }
    '^tabprobe$'    { $cm = @{ cmd = 'tabprobe' } }
    '^noteread$'    { $cm = @{ cmd = 'noteread' } }
    '^diag$'        { $cm = @{ cmd = 'diag' } }
    '^count$'       { $cm = @{ cmd = 'count' } }
    '^tabwrite:(?s)(.+)$'  { $cm = @{ cmd = 'tabwrite';  text = $Matches[1] } }
    '^notepush:(?s)(.+)$'  { $cm = @{ cmd = 'notepush';  mode = 'notes'; text = $Matches[1] } }
    '^sync:(?s)(.+)$'      { $cm = @{ cmd = 'notepush';  mode = 'auto';  text = $Matches[1] } }
    '^act:([^:]+):([^:]+)(?::(.*))?$' {
        $cm = @{ cmd = 'act'; guid = $Matches[1]; verb = $Matches[2] }
        if ($Matches[3]) { $cm['value'] = $Matches[3] }
    }
    # setState:<guid>:<json>  -- counters store their number in LuaScriptState, which
    # the generic act: form cannot carry because the JSON contains colons and quotes.
    # Built as a hashtable here so ConvertTo-Json does the escaping.
    '^setState:([^:]+):(?s)(.+)$' {
        $cm = @{ cmd = 'act'; guid = $Matches[1]; verb = 'setScriptState'; value = $Matches[2] }
    }
    # getState:<guid>
    '^getState:([^:]+)$' {
        $cm = @{ cmd = 'act'; guid = $Matches[1]; verb = 'getScriptState' }
    }
    # call:<guid>:<functionName>  -- invoke a function inside that OBJECT's own script.
    # Needed for the 金券 counters: their on-screen number is repainted by their own
    # customSet()/updateDisplay(), so setting script_state alone leaves it stale.
    '^call:([^:]+):([^:]+)$' {
        $cm = @{ cmd = 'call'; guid = $Matches[1]; fn = $Matches[2] }
    }
    # setCount:<guid>:<int>  -- the whole "make the counter show N" recipe in one call
    '^setCount:([^:]+):(-?\d+)$' {
        $cm = @{ cmd = 'setcount'; guid = $Matches[1]; value = $Matches[2] }
    }
    # find:<filter>
    '^find:(?s)(.*)$' { $cm = @{ cmd = 'find'; filter = $Matches[1] } }
    # all:<n> / index:<n>  -- LIVE full-table scan straight out of the running game
    # (not the autosave, which lags up to ~5 min). Pair with -Raw and parse the JSON:
    # that is how "what did the player just do?" gets answered. See live_index.ps1.
    '^all:(\d+)$'   { $cm = @{ cmd = 'all';   limit = $Matches[1] } }
    '^index:(\d+)$' { $cm = @{ cmd = 'index'; limit = $Matches[1] } }
    # hand:<Color>:<get|take|holding|give|draw>[:<guid>[:<n>]]
    #   get     list the hand zone       take    hand a table object to that colour
    #   holding what that colour holds    give    hand ONE specific guid to that colour
    #   draw    move n cards from a container into that colour's hand (deck.deal, else the fallback)
    '^hand:(\w+):(\w+)$' { $cm = @{ cmd = 'hand'; player = $Matches[1]; action = $Matches[2] } }
    '^hand:(\w+):(\w+):([^:]+)$' { $cm = @{ cmd = 'hand'; player = $Matches[1]; action = $Matches[2]; guid = $Matches[3] } }
    '^hand:(\w+):(\w+):([^:]+):(\d+)$' { $cm = @{ cmd = 'hand'; player = $Matches[1]; action = $Matches[2]; guid = $Matches[3]; n = $Matches[4] } }
    # container:<guid>  -- what is actually inside a Bag/Deck right now (complements index/draw/take)
    # container:<guid>:full  -- same, but the WHOLE face text instead of a 60-char prefix. Needed to
    #   build the card library: the face text exists nowhere else (obj_index/live_index stop at name).
    '^container:([^:]+):full$' { $cm = @{ cmd = 'container'; guid = $Matches[1]; full = '1' } }
    '^container:([^:]+)$' { $cm = @{ cmd = 'container'; guid = $Matches[1] } }
    # ---- v14-primitives (2026-10-09): the operations a trained control layer kept missing ----
    # players                                  -> who is at the table, whose turn, hand COUNT
    '^players$' { $cm = @{ cmd = 'players' } }
    # player:<Color>:<turn|blind>[:<true|false>]  -> TTS's own turn marker / blindfold
    '^player:(\w+):(\w+)(?::(\w+))?$' {
        $cm = @{ cmd = 'player'; player = $Matches[1]; action = $Matches[2] }
        if ($Matches[3]) { $cm.on = $Matches[3] }
    }
    # take:<deck guid>:<CardID>:<x>:<y>:<z>[:<1|0 faceup>]  -- pull ONE NAMED card out of a deck.
    # CardID empty is allowed (`::`) and means the top card, i.e. the same thing draw: does.
    '^take:([^:]+):([^:]*):([^:]+):([^:]+):([^:]+)(?::([01]))?$' {
        $cm = @{ cmd = 'take'; deckguid = $Matches[1]; cardid = $Matches[2]
                 x = $Matches[3]; y = $Matches[4]; z = $Matches[5] }
        if ($Matches[6]) { $cm.faceup = $Matches[6] }
    }
    # destroy:<guid>                           -> remove an object from the table
    '^destroy:([^:]+)$' { $cm = @{ cmd = 'destroy'; guid = $Matches[1] } }
    # token_plain[:x:y:z]                      -> build the turn token by CLONING a table tile.
    #   clone() never opens TTS's custom-tile dialog, which spawnObject always did (see DSH_tokenPlain)
    '^token_plain(?::(-?[\d.]+):(-?[\d.]+):(-?[\d.]+))?$' {
        $cm = @{ cmd = 'token_plain' }
        if ($Matches[1]) { $cm.x = $Matches[1]; $cm.y = $Matches[2]; $cm.z = $Matches[3] }
    }
    # spawn_step                               -> the second half of `spawn:type` (see DSH_spawnStep:
    #   spawnObject stops the bridge thread, so the reply goes first and the piece is built here)
    '^spawn_step$' { $cm = @{ cmd = 'spawn_step' } }
    # spawn is the one command whose payload is JSON (colons and quotes inside), so only the SHORT
    # forms get a command-line syntax. Everything else goes through -Json with a full envelope:
    #   ds.ps1 -Json '{"messageID":2,"customMessage":{"cmd":"spawn","json":"{\"Name\":\"Custom_Tile\"}","x":5,"y":2,"z":0}}'
    #   spawn:type:<TTS type>:<x>:<y>:<z>       -> e.g. spawn:type:Custom_Tile:5:2:0
    '^spawn:type:([^:]+):([^:]+):([^:]+):([^:]+)$' {
        $cm = @{ cmd = 'spawn'; type = $Matches[1]; x = $Matches[2]; y = $Matches[3]; z = $Matches[4] }
    }
    #   spawn:copy:<guid>:<x>:<y>:<z>           -> clone an existing object (keeps its art/Lua/state)
    '^spawn:copy:([^:]+):([^:]+):([^:]+):([^:]+)$' {
        $cm = @{ cmd = 'spawn'; copyguid = $Matches[1]; x = $Matches[2]; y = $Matches[3]; z = $Matches[4] }
    }
    # deal:<deckGuid>:<n>:<Color>  -- TTS's own "draw the top n cards" primitive.
    # The generic act: form can only carry `value`, not `player`, and deal() needs the
    # player colour, so it gets its own pattern.
    '^deal:([^:]+):(\d+):(\w+)$' {
        $cm = @{ cmd = 'act'; guid = $Matches[1]; verb = 'deal'; value = $Matches[2]; player = $Matches[3] }
    }
    # flip:<guid>  -- adds 180 to the card's Z rotation, i.e. turns it over
    '^flip:([^:]+)$' { $cm = @{ cmd = 'act'; guid = $Matches[1]; verb = 'flip' } }
    # draw:<deckGuid>:<n>:<x>:<y>:<z>[:<faceup 0|1>]  -- take n cards OFF the top of a
    # deck and lay them out in a row. A card inside a Deck is NOT an addressable object,
    # so this is the only way to draw; see the `draw` handler in dsh_global.lua.
    '^draw:([^:]+):(\d+):([^:]+):([^:]+):([^:]+)(?::([01]))?$' {
        $cm = @{ cmd = 'draw'; guid = $Matches[1]; n = $Matches[2]; x = $Matches[3]; y = $Matches[4]; z = $Matches[5] }
        if ($Matches[6]) { $cm['faceup'] = $Matches[6] }
    }
    # geom: one call for a whole set of objects' table/local/bounds geometry, so
    # converting an artwork pixel to a table coordinate costs one round trip.
    '^geom:(?s)(.+)$' { $cm = @{ cmd = 'geom'; guids = $Matches[1] } }
    # move/rotate go through the dedicated handlers in Lua, not the generic act():
    # act's setPosition built the argument as a Lua table and TTS rejected it with
    # "cannot convert a userdata to a clr type UnityEngine.Vector3", while moveTo()
    # calls the same method with a plain positional table and succeeds.
    '^move:([^:]+):([^:]+):([^:]+):(.+)$' {
        $cm = @{ cmd = 'move'; guid = $Matches[1]; x = $Matches[2]; y = $Matches[3]; z = $Matches[4] }
    }
    '^rotate:([^:]+):([^:]+):([^:]+):(.+)$' {
        $cm = @{ cmd = 'rotate'; guid = $Matches[1]; x = $Matches[2]; y = $Matches[3]; z = $Matches[4] }
    }
    # read:<guid> / meta:<guid> / probe:<guid>  -- full per-object dump (read includes
    # GMNotes, which is where the 源石/源岩/异铁 counters keep their number; their
    # script_state is empty, so getState:<guid> returns nothing for them).
    '^read:([^:]+)$'  { $cm = @{ cmd = 'read';  guid = $Matches[1] } }
    '^meta:([^:]+)$'  { $cm = @{ cmd = 'meta';  guid = $Matches[1] } }
    '^probe:([^:]+)$' { $cm = @{ cmd = 'probe'; guid = $Matches[1] } }
    default { $cm = @{ cmd = $Do } }
}

if ($TextFile -ne '') {
    if (-not (Test-Path -LiteralPath $TextFile)) { Write-Host "ERR no such text file: $TextFile"; return }
    $body = [System.IO.File]::ReadAllText($TextFile, [System.Text.Encoding]::UTF8)
    switch -Regex ($Do) {
        '^tabwrite'  { $cm = @{ cmd = 'tabwrite'; text = $body } }
        '^notepush'  { $cm = @{ cmd = 'notepush'; mode = 'notes'; text = $body } }
        '^sync'      { $cm = @{ cmd = 'notepush'; mode = 'auto';  text = $body } }
        default      { Write-Host "ERR -TextFile only supports tabwrite/notepush/sync"; return }
    }
}

if ($Json -ne '') { $envelope = $Json }
else { $envelope = @{ messageID = 2; customMessage = $cm } | ConvertTo-Json -Depth 8 -Compress }

$r = Send-TTS $envelope $TimeoutSec
if ($r.err) { Write-Host ("ERR {0}" -f $r.err); return }
# NOTE: everything here uses `return`, not `exit`. This script is now ALSO called
# in-process (`& ds.ps1 ... 6>&1`) by live_index.ps1, and a top-level `exit` would
# kill that caller too. `return` ends the script either way; the only thing lost is
# the process exit code, which no caller reads (they all parse the printed text).
if ($Raw) { Write-Host $r.json; return }

$resp = $null
try { $resp = ($r.json | ConvertFrom-Json).customMessage } catch { Write-Host ("PARSE-FAIL {0}" -f $r.json); return }

$cmOut = $null
if ($resp.PSObject.Properties.Name -contains 'cmd') { $cmOut = $resp.cmd }
$okv = $resp.ok
if ($okv -ne $true) {
    Write-Host ("FAIL cmd={0} err={1}" -f $cmOut, $resp.err)
    return
}

# ------------------------------------------------------------------- output ---
# One line per call. Bodies are never echoed unless -Tail asks for them.
switch ($cmOut) {
    'ping' { Write-Host ("ok v={0} objs={1} loads={2} at={3}" -f $resp.v, $resp.objects, $resp.loads, $resp.at) }
    'tabread' {
        $line = "ok tabread chars={0} idx={1} title={2}" -f $resp.chars, $resp.editIndex, $resp.title
        if ($Tail -gt 0 -and $resp.body) {
            $b = [string]$resp.body
            if ($b.Length -gt $Tail) { $b = $b.Substring($b.Length - $Tail) }
            # collapse newlines so it stays one line
            $line += " | tail: " + ($b -replace "`r?`n", ' / ')
        }
        Write-Host $line
    }
    'tabwrite' {
        $line = "ok tabwrite sent={0} readback={1} verified={2} idx={3}" -f $resp.sentChars, $resp.readbackChars, $resp.verified, $resp.usedIndex
        if ($Tail -gt 0 -and $resp.titleAfter) { $line += " title=$($resp.titleAfter)" }
        Write-Host $line
    }
    'notepush' { Write-Host ("ok notepush sent={0} setNotes={1} verified={2}" -f $resp.sentChars, $resp.setNotes, $resp.notesVerified) }
    'act'      { Write-Host ("ok act {0} {1} -> {2}" -f $resp.guid, $resp.verb, $resp.result) }
    'tablist'  {
        Write-Host ("ok tabs={0} dialoguePos={1}" -f $resp.count, $resp.dialoguePos)
        foreach ($t in $resp.tabs) {
            Write-Host ("  pos={0} idx={1} chars={2} dsh={3} {4}" -f $t.listPos, $t.editIndex, $t.chars, $t.isDialogue, $t.title)
        }
    }
    'count'    { Write-Host ("ok total={0} distinct={1}" -f $resp.total, $resp.distinct) }
    # ---- v14-primitives -------------------------------------------------------------------------
    # players: `items` arrives as a JSON string (the bridge flattens nested tables before sending,
    # because sendExternalMessage cannot serialise a nested table - see the SILENT-REPLY note in
    # dsh_global.lua). Parse it back and print one line per seat.
    'players'  {
        Write-Host ("ok players count={0} turn_order={1}" -f ($resp.count -join ','), ($resp.turn_order -join ','))
        # The bridge hands back ONE DELIMITER-JOINED STRING PER SEAT on purpose: nested objects do NOT
        # survive the reply's flattening (measured live - every field came back empty).
        foreach ($s in @($resp.seats)) {
            $f = @($s -split '\|')
            Write-Host ("  {0,-6} hand={1,-4} seated={2,-6} host={3,-6} admin={4,-6} blind={5,-6} {6}" -f `
                $f[0], $f[2], $f[5], $f[3], $f[4], $f[6], $f[1])
        }
    }
    'take'     {
        Write-Host ("ok take card={0} guid={1} face={2} rotZ={3} remaining={4} name={5}" -f `
            $resp.cardid, $resp.guid, $resp.face, $resp.rotZ, $resp.remaining, $resp.name)
    }
    'spawn'    {
        Write-Host ("ok spawn mode={0} guid={1} name={2}" -f $resp.mode, $resp.guid, $resp.name)
    }
    'destroy'  { Write-Host ("ok destroy guid={0}" -f $resp.guid) }
    'player'   { Write-Host ("ok player color={0} action={1}" -f $resp.color, $resp.action) }
    # hand: `items` arrives as a JSON string (nested tables are flattened by the bridge)
    'hand'     {
        Write-Host ("ok hand player={0} action={1} count={2} hand={3}" -f $resp.player, $resp.action, $resp.count, $resp.hand)
        $items = @()
        if ($resp.items) { try { $items = @($resp.items | ConvertFrom-Json) } catch { $items = @() } }
        foreach ($it in $items) { Write-Host ("  {0,-9} {1}" -f ($it.guid -join ','), ($it.name -join ',')) }
    }
    # container: what is inside a Bag/Deck right now. Each line is "guid|name|nick|qty|description",
    # where description is a short prefix of the card's face text (the full text is read:<guid>).
    'container' {
        Write-Host ("ok container guid={0} count={1} quantity={2}" -f `
            ($resp.guid -join ','), ($resp.count -join ','), ($resp.quantity -join ','))
        # `lines` arrives as an array whose single element is a JSON string (the bridge's flattening
        # does that to any list), so unwrap it, then slice each line.
        # Keep this block DUMB on purpose. Three attempts died here on PowerShell traps that reported
        # the WRONG line, so avoid all of them: no -join with an empty operand (it binds as a switch),
        # no -like '[*' (an unmatched `[` is an invalid wildcard pattern), no nested expression.
        # Index the array and test the character instead.
        $parts = @($resp.lines)
        $rows = @()
        foreach ($p in $parts) {
            $s = [string]$p
            if ($s.Length -gt 0 -and $s[0] -eq '[') {
                try { foreach ($r in @($s | ConvertFrom-Json)) { $rows += $r } } catch { }
            } elseif ($s -ne '') { $rows += $s }
        }
        foreach ($s in $rows) {
            $f = @([string]$s -split '\|')
            Write-Host ("  {0,-9} {1,-26} nick={2,-12} qty={3} tags={4}" -f $f[0], $f[1], $f[2], $f[3], $f[4])
        }
    }
    'draw'     {
        Write-Host ("ok draw deck={0} took={1} remaining={2} guids={3}" -f $resp.deck, $resp.n, $resp.remaining, ($resp.guids -join ','))
    }
    default    {
        $s = Fmt $resp
        if ($s.Length -gt 300) { $s = $s.Substring(0, 300) + '...' }
        Write-Host ("ok {0} {1}" -f $cmOut, $s)
    }
}
