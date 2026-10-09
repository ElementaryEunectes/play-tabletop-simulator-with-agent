# test_doc_refs.ps1 - every path a tracked .md points at, that is meant to ship, must exist.
#
# WHY
#   The docs ARE this project's interface, and nothing checked them. On 2026-10-08 a split moved the
#   game docs into local\games\ and left PLAY.md (read every turn) pointing at
#   tts\docs\DICETHRONE_FLOW.md, which no longer existed. All three tests stayed green; the stale
#   pointer was found by hand. This is the missing guard.
#
# SCOPE
#   * only tokens with a DIRECTORY separator starting at a repo-relative root (tts\ local\ cache\
#     out\ logs\ shots\ archive\) plus the root files (AGENTS.md HANDOFF.md README.md README.en.md
#     CONTRIBUTING.md LICENSE start-agent.ps1). Those break when something moves.
#     Bare filenames like `roll.ps1` are prose, not paths - v1 flagged ~270 of those and was useless.
#   * a backticked token is often a COMMAND (`tts\play.ps1 turn`) or carries an annotation
#     (`tts\docs\TTS_RULES.md（§二 工具清单）`): take only the first word.
#   * FAIL for a missing path that should ship; INFO for gitignored trees (cache\ out\ local\ logs\
#     shots\ archive\) and for lines about archived material (those scripts live in
#     ~\.dsh\archive\tts-legacy\, so their absence from the repo is correct).
#   * skip placeholders (<game>, <游戏>, *), variables ($DSH_HOME\...), URLs, npm paths, ~ paths.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_doc_refs.ps1
#   exit 0 = every shipped path resolves, exit 1 = at least one does not
param([string]$Root = '')
$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$Root = (Resolve-Path -LiteralPath $Root).Path

$informRoots = @('cache\', 'out\', 'local\', 'logs\', 'shots\', 'archive\')
$rootFiles = @('AGENTS.md', 'HANDOFF.md', 'README.md', 'README.en.md', 'CONTRIBUTING.md', 'LICENSE', 'start-agent.ps1', 'start.cmd')
$missing = @(); $informed = @(); $checked = 0
# Through cmd into a FILE: under the workspace-write confinement piped capture of a grandchild is
# silently lost, which used to make this test report "no tracked .md files found" (2026-10-09).
$tmpGit = Join-Path ([System.IO.Path]::GetTempPath()) ('docrefs_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
& cmd /c ('git -C "{0}" ls-files "*.md" > "{1}" 2>&1' -f $Root, $tmpGit)
$files = @()
if (Test-Path -LiteralPath $tmpGit) {
    $files = @([System.IO.File]::ReadAllLines($tmpGit, [System.Text.Encoding]::UTF8) | Where-Object { $_ -and $_ -notmatch '^(fatal|warning|error)' })
    Remove-Item -LiteralPath $tmpGit -Force -ErrorAction SilentlyContinue
}
if ($files.Count -eq 0) { Write-Host 'FAIL  no tracked .md files found (run this inside the repo)'; exit 1 }

foreach ($rel in $files) {
    $full = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($full, [System.Text.Encoding]::UTF8)) {
        $lineNo++
        foreach ($m in [regex]::Matches($line, '`([^`]+)`')) {
            $tok = ($m.Groups[1].Value.Trim() -split '[\s（(]')[0]
            if ($tok.Length -lt 4 -or $tok.Length -gt 120) { continue }
            if ($tok -match '<|>|\*|\||\$|@|^~') { continue }
            if ($tok -match '^(https?|mailto):') { continue }
            $probe = ($tok -replace '/', '\').TrimEnd('\')
            $isRootedPath = $probe -match '^(tts|local|cache|out|logs|shots|archive)\\'
            $isRootFile = $rootFiles -contains $probe
            if (-not ($isRootedPath -or $isRootFile)) { continue }
            $checked++
            if (Test-Path -LiteralPath (Join-Path $Root $probe)) { continue }
            $isInform = $false
            foreach ($i in $informRoots) { if ($probe.StartsWith($i)) { $isInform = $true; break } }
            if ($line -match '归档|archive|tts-legacy') { $isInform = $true }
            $entry = "{0}:{1}  {2}" -f $rel, $lineNo, $tok
            if ($isInform) { $informed += $entry } else { $missing += $entry }
        }
    }
}
"checked $checked repo-relative reference(s) in $($files.Count) tracked .md files"
if ($informed.Count -gt 0) {
    Write-Host ("INFO  {0} reference(s) are absent by design (gitignored or archived):" -f $informed.Count)
    $informed | Select-Object -First 5 | ForEach-Object { Write-Host ("      " + $_) }
    if ($informed.Count -gt 5) { Write-Host ("      ... and {0} more" -f ($informed.Count - 5)) }
}
if ($missing.Count -gt 0) {
    Write-Host ("`nFAIL  {0} shipped path reference(s) do not exist:" -f $missing.Count)
    $missing | ForEach-Object { Write-Host ("      " + $_) }
    exit 1
}
Write-Host "`nall shipped path references resolve"
