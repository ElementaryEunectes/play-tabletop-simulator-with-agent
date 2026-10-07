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
    [int]$MaxLocalBytes = 2048          # so is the machine-local overlay
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
try { $tracked = @(& git -C $Root ls-files) } catch { }
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
    $tplPath = Join-Path $Root 'tts\docs\HARNESS_HOME_AGENTS.template.md'
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
