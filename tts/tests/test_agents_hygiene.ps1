# test_agents_hygiene.ps1 - the three instruction slots must stay in their lanes.
#
# WHY
#   Isolation is a discipline, not a feature. Nothing in the harness stops the project charter
#   from growing, from absorbing machine facts that belong in the (gitignored) local overlay,
#   or from leaking a real user name into a public repository. The harness injects all of it on
#   EVERY request, so drift is paid for forever. This test is that discipline, and it needs no
#   TTS, no save and no Node.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_agents_hygiene.ps1
#   exit 0 = all checks passed, exit 1 = at least one violation
#
# The user name is read from the environment, so the leak check works on any machine.
param(
    [string]$Root = '',                 # defaults to the repository root (tts\tests -> repo)
    [int]$MaxProjectBytes = 3840,   # 3656 measured after the boundary rule; the rule is worth its bytes       # the committed charter is injected every request
    [int]$MaxLocalBytes = 4096          # the machine-local overlay now also carries the platform
                                      # subset this project needs (method A: no global slot at all),
                                      # so its budget grew from 2048; it stays far below the project one
)
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }

$script:failed = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail) {
    if ($Ok) { Write-Host ("PASS  {0}" -f $Name) }
    else { $script:failed++; Write-Host ("FAIL  {0}   <- {1}" -f $Name, $Detail) -ForegroundColor Red }
}
function Read-Utf8([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

# ---- 1. the committed charter: present, lean, and still saying the load-bearing things ----
$agentsPath = Join-Path $Root 'AGENTS.md'
$agents = Read-Utf8 $agentsPath
Check 'repo AGENTS.md exists' ($null -ne $agents) $agentsPath
if ($null -ne $agents) {
    $bytes = (Get-Item -LiteralPath $agentsPath).Length
    Check ("repo AGENTS.md <= {0} B (is {1})" -f $MaxProjectBytes, $bytes) ($bytes -le $MaxProjectBytes) `
        'it is injected on every request: put detail in HANDOFF/PLAY and leave a pointer here'
    # ASCII markers on purpose: they survive any rewording of the Chinese prose around them.
    foreach ($marker in @('start-agent.ps1', 'PLAY.md', 'local\games', 'tts\config.ps1', 'check_ps1.ps1')) {
        Check ("charter still mentions " + $marker) ($agents -like ('*' + $marker + '*')) `
            'a rule disappeared during a trim - the load-bearing pointers must stay'
    }
}

# ---- 2. nothing tracked may carry a machine path or the real user name ----
$user = [string]$env:USERNAME
$tracked = @()
# Through cmd into a FILE: piped capture of a grandchild is silently lost under the workspace-write
# confinement, which made the audit see zero tracked files (2026-10-09).
$tracked = @()
try {
    $tmpLs = Join-Path ([System.IO.Path]::GetTempPath()) ('hyg_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    & cmd /c ('git -C "{0}" ls-files > "{1}" 2>&1' -f $Root, $tmpLs)
    if (Test-Path -LiteralPath $tmpLs) {
        $tracked = @([System.IO.File]::ReadAllLines($tmpLs, [System.Text.Encoding]::UTF8) | Where-Object { $_ })
        Remove-Item -LiteralPath $tmpLs -Force -ErrorAction SilentlyContinue
    }
} catch { }
Check 'git ls-files works (audit needs git)' ($tracked.Count -gt 0) 'run this from a git checkout'
if ($tracked.Count -gt 0) {
    $leaks = @()
    foreach ($rel in $tracked) {
        $full = Join-Path $Root $rel
        $body = Read-Utf8 $full
        if ($null -eq $body) { continue }
        if ($user -ne '' -and $body -like ('*' + $user + '*')) { $leaks += ($rel + ': user name') }
        # A placeholder (C:\Users\<name>) is fine; a real one is not. The name must start with an
        # alphanumeric, which keeps 'C:\Users\...' (a placeholder in a comment) and this pattern's
        # own source text from being reported as leaks.
        foreach ($m in [regex]::Matches($body, 'C:\\Users\\([A-Za-z0-9][A-Za-z0-9._-]*)')) {
            $leaks += ($rel + ': absolute user path')
        }
    }
    Check 'no user names or absolute user paths in tracked files' ($leaks.Count -eq 0) `
        (($leaks | Select-Object -First 4) -join ' | ')
}

# ---- 2a. nothing private may be TRACKED, whatever .gitignore says ----
# WHY: on 2026-10-09 the control layer was moved to local\games\<game>\control\ and `git add -A`
# committed all four files anyway. local/ IS in .gitignore, but that does not help a file git has
# already seen: an ignored path that is tracked stays tracked, so the "private, never shipped"
# promise was broken by the very commit that was supposed to enforce it. Check the INDEX, not the
# ignore rules.
if ($tracked.Count -gt 0) {
    $private = @($tracked | Where-Object { ($_ -replace '\\', '/') -like 'local/*' })
    Check 'nothing under local\ is tracked (private stays private)' ($private.Count -eq 0) `
        (($private | Select-Object -First 4) -join ' | ') + '  <- git rm --cached, and keep the files'
}

# ---- 2b. the open-source boundary: no REAL game name in any tracked file ----
# WHY: this repo may only ship what is true for ANY TTS mod (tts\docs\README.md). A real game name
# in a tracked file is that rule's most common violation, and on 2026-10-09 an audit found 14 of 71
# tracked files carrying one while EVERY gate still said PASS - the validator was simply blind to
# it. Same "reports success without looking" failure this repo already paid for twice.
#
# HOW THE NAMES ARE STORED (read this before editing the list):
#   * ASCII only, assembled at runtime from code points - never typed as literals. Two reasons:
#     (a) typed whole, this file would match its own scan;
#     (b) this file is deliberately non-ASCII-free so that a lost UTF-8 BOM cannot silently mangle
#         literals: on 2026-10-09 an edit dropped the BOM here, Windows PowerShell decoded the CJK
#         bytes as ANSI, and the file died with "Unexpected token" - the resulting garbage was then
#         frozen in by check_ps1.ps1, which re-saved it WITH a BOM. The self-check below guards that.
#   * to ADD a name: append its code points as a second array argument, then re-run. The length
#     control below fails loudly if the list and the pattern ever disagree.
#   * the ONLY exemption is the licence section of the two READMEs: an attribution has to let the
#     rights holder be identified, so a blanket ban there would be wrong rather than strict. Keep
#     this list short - anywhere else write <game> or a description instead.
$script:gameCp = @(
    @(0x64, 0x69, 0x63, 0x65, 0x74, 0x68, 0x72, 0x6F, 0x6E, 0x65),                  # a match-shaped board game
    @(0x71, 0x69, 0x73, 0x68, 0x65, 0x6E, 0x67),                                      # this machine's GAME= slug
    @(0x4E03, 0x5723),                                                                # that mod's name (one word)
    @(0x738B, 0x6743, 0x9AB0, 0x94F8),                                                # the first game taught
    @(0x6E38, 0x57CE, 0x62D3, 0x8352),                                                # the archived ended game
    @(0x94F8, 0x57FA, 0x8005),                                                        # the ended game's subtitle
    @(0x6E, 0x6F, 0x6D, 0x61, 0x64, 0x63, 0x69, 0x74, 0x79),                          # its slug in the archive
    @(0x660E, 0x65E5, 0x65B9, 0x821F)                                                 # that game's franchise
)
$script:gameWord = @($script:gameCp | ForEach-Object { -join ($_ | ForEach-Object { [char]$_ }) })
$script:gamePattern = ($script:gameWord -join '|')
$nameExempt = @('README.md', 'README.en.md')          # licence/attribution sections only
if ($tracked.Count -gt 0) {
    $nameLeaks = @()
    foreach ($rel in $tracked) {
        # Compare the BASENAME: git ls-files returns repo-relative paths like tts/tests/x.ps1, so a
        # bare-name exemption list would silently never match (it did not, on the first try).
        $base = Split-Path -Leaf $rel
        if ($nameExempt -contains $base) { continue }
        $body = Read-Utf8 (Join-Path $Root $rel)
        if ($null -eq $body) { continue }
        foreach ($m in [regex]::Matches($body, $script:gamePattern, 'IgnoreCase')) { $nameLeaks += ($rel + ': ' + $m.Value) }
    }
    Check 'no real game names in tracked files (open-source boundary)' ($nameLeaks.Count -eq 0) `
        ((($nameLeaks | Select-Object -Unique | Select-Object -First 4) -join ' | ') + '  <- write <game> or a description instead')
}
# Positive controls. Both must hold, and each catches a DIFFERENT way this check can rot:
#   control 1 - the scanner sees a planted name. Without it, a pattern that matches nothing passes
#               every scan; a blind leak check is worse than no leak check;
#   control 2 - the pattern still has one branch per word. On 2026-10-09 the array was written as
#               @('a' + 'b', 'c' + 'd'), which does NOT build two elements (the comma folds into the
#               concatenation), so the joined pattern had no "|" at all - and control 1 did NOT
#               catch it, because $gameWord[0] then returned that same broken string, so probe and
#               pattern were broken identically and matched each other. Two green checks are not
#               proof; the "alt=" counter is printed so a wide render cannot hide a collapse.
$probe = 'this save came from ' + $script:gameWord[0]
Check 'game-name scanner sees a planted name (positive control)' `
    ([regex]::IsMatch($probe, $script:gamePattern, 'IgnoreCase')) `
    'the scanner is blind - fix it before trusting the check above'
$altCount = ($script:gamePattern -split '\|').Count
Check ("game-name pattern has one branch per name (alt={0} of {1})" -f $altCount, $script:gameWord.Count) `
    ($altCount -eq $script:gameWord.Count) 'the alternation collapsed - check how the array is built'
# Structure control: the list must hold exactly the names someone decided to ban. This is what
# caught the 2026-10-09 slip where a later edit silently ate one line of the array: the alternation
# check still passed (7 of 7 agreed), the licence control still passed, and one real name had
# quietly stopped being scanned. ADD A NAME HERE AND BUMP THE NUMBER - a deliberate act, not a typo.
$expectedNames = 8
Check ("game-name list is complete ({0} entries, expected {1})" -f $script:gameWord.Count, $expectedNames) `
    ($script:gameWord.Count -eq $expectedNames) 'the list and $expectedNames disagree - add/bump deliberately'
# Self-check: this file must stay ASCII apart from the UTF-8 BOM. A non-BOM byte above 0x7F here
# means someone pasted a CJK literal back in, which is exactly the BOM-fragility that broke this
# file once already (Windows PowerShell read the CJK bytes as ANSI and died on "Unexpected token").
$selfPath = $MyInvocation.MyCommand.Path
if ($selfPath) {
    $raw = [IO.File]::ReadAllBytes($selfPath)
    $skip = 0
    if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { $skip = 3 }
    $nonAscii = @($raw[$skip..($raw.Length - 1)] | Where-Object { $_ -gt 0x7F }).Count
    Check ("this test file is ASCII apart from the BOM (non-ASCII bytes: {0})" -f $nonAscii) ($nonAscii -eq 0) `
        'keep the denylist in code points; a stray CJK literal here is BOM-fragile'
}

# ---- 3. the machine slot: ignored by git, and small enough to be worth injecting ----
$ignored = $false
try { & git -C $Root check-ignore -q 'AGENTS.local.md'; $ignored = ($LASTEXITCODE -eq 0) } catch { }
Check 'AGENTS.local.md is gitignored' $ignored 'machine facts must never be committable'

$localPath = Join-Path $Root 'AGENTS.local.md'
if (Test-Path -LiteralPath $localPath) {
    $n = (Get-Item -LiteralPath $localPath).Length
    Check ("AGENTS.local.md <= {0} B (is {1})" -f $MaxLocalBytes, $n) ($n -le $MaxLocalBytes) `
        'it is injected too: machine facts only, no project rules'
} else {
    Write-Host 'INFO  AGENTS.local.md absent on this machine (normal for a fresh clone)'
}

# ---- 4. harness-home slot: report it, and check it against its versioned source ----
$homeAgents = ''
if ($env:DSH_HOME) { $homeAgents = Join-Path $env:DSH_HOME 'AGENTS.md' }
if ($homeAgents -ne '' -and (Test-Path -LiteralPath $homeAgents)) {
    $n = (Get-Item -LiteralPath $homeAgents).Length
    Write-Host ("INFO  harness-home AGENTS.md = {0} B (injected as well, and NOT tracked by this repo)" -f $n)
    if ($n -gt 4096) { Write-Host 'WARN  it is larger than the repo charter - generic rules should be shorter than project ones' -ForegroundColor Yellow }

    # ---- 5. it must equal the body of the committed template, or the two have drifted ----
    # The charter template moved OUT of this repository on 2026-10-09 (it is platform layer, harness
# home). Look there first; keep the old in-repo path as a fallback so an older checkout still works.
$tplPath = ''
foreach ($cand in @(
    $(if ($env:DSH_HOME) { Join-Path $env:DSH_HOME 'platform\HARNESS_HOME_AGENTS.template.md' }),
    (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh\platform\HARNESS_HOME_AGENTS.template.md'),
    (Join-Path $Root 'tts\docs\HARNESS_HOME_AGENTS.template.md')
)) { if ($cand -and (Test-Path -LiteralPath $cand)) { $tplPath = $cand; break } }
    $tpl = Read-Utf8 $tplPath
    if ($null -ne $tpl) {
        $lines = $tpl -split "`r?`n"
        $sep = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq '---') { $sep = $i; break } }
        if ($sep -ge 0) {
            $body = ((($lines[($sep + 1)..($lines.Count - 1)]) -join "`n") -replace "`r`n", "`n").Trim()
            $installed = ((Read-Utf8 $homeAgents) -replace "`r`n", "`n").Trim()
            Check 'harness-home AGENTS.md matches the template body' ($body -eq $installed) `
                'drifted: copy the template body (everything after the first --- line) over it'
        } else {
            Write-Host 'INFO  template has no --- separator; drift not checked'
        }
    }
} else {
    Write-Host 'INFO  no harness-home AGENTS.md to compare (DSH_HOME unset or file absent)'
}

if ($script:failed -gt 0) { Write-Host ("`n{0} check(s) FAILED" -f $script:failed); exit 1 }
Write-Host "`nall checks passed"
