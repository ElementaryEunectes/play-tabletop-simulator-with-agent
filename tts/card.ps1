#Requires -Version 5.1
<#
  card.ps1 -- "one command to look up a card", for whichever mod is current.
  usage:  card.ps1 -Q '<name or fragment>'      (English/pinyin aliases too: -Q hex , -Q bow)
  data:   cache\<game>_cards.md    the text library, built when the mod was taught (read-only here)
          cache\<game>_alias.json  alias table: the player's word -> the card names it means.
                                   GAME DATA, so it is NOT in this script. Missing file = plain text
                                   matching, and the hint only appears when a query actually fails.
  output: 1~3 lines (name / cost+dice / effect / source); on no match, NOT FOUND + closest candidates.
  never invents content: no match means it says so.
  NOTE:   both data paths are parameters (defaulted from tts\config.ps1) so a test or another game
          can point them elsewhere - nothing here hard-codes a game's file names.
#>
param(
    [Parameter(Position = 0)]
    [string]$Q = '',
    [int]$Max = 3,
    # NOT -Db: `db` is the parameter ALIAS of the common parameter -Debug, and this script is an
    # advanced one (the [Parameter()] above gives it common parameters), so -Db is refused with
    # "conflicts with the parameter alias of the same name for parameter 'Debug'".
    # NOTE: `Get-Alias db` prints NOTHING - these aliases belong to the parameter set, not to the
    # alias table. The self-check for a new parameter name is the common-parameter alias list:
    # db ea ev wa wv ov ob pv vb ia iv.
    [string]$CardsFile = '',
    [string]$AliasFile = '',
    [switch]$Full
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# A missing -Q used to make PowerShell itself dump a multi-line mandatory-parameter error
# (~630 bytes of context for nothing). Answer it ourselves, in two lines. NOTE: this runs BEFORE
# config.ps1 is dot-sourced (no need for it here), and `exit 2` is deliberate for a CLI tool whose
# stdout is the answer - see the header of tts\bootstrap.ps1 for the two conventions.
if ([string]::IsNullOrWhiteSpace($Q)) {
    Write-Output "usage: card.ps1 -Q '<name or fragment>'   (data: cache\<game>_cards.md)"
    exit 2
}

# WHICH files: from the GAME= line in local\games\_current.md, via tts\config.ps1. Backfill AFTER
# the dot-source - a param default cannot reference a config variable (it is not evaluated yet).
. (Join-Path $PSScriptRoot 'config.ps1')
if ($CardsFile -eq '') { $CardsFile = $DshGameCards }
if ($AliasFile -eq '') { $AliasFile = $DshGameAlias }
if ($CardsFile -eq '') { Write-Output 'NOT FOUND (no current game: set GAME= in local\games\_current.md)'; exit 1 }
$db = [System.IO.Path]::GetFullPath($CardsFile)
if (-not (Test-Path -LiteralPath $db)) {
    Write-Output "NOT FOUND (文本库不存在: $db)"
    exit 1
}

$lines = Get-Content -LiteralPath $db -Encoding UTF8
$cards = New-Object System.Collections.ArrayList
foreach ($l in $lines) {
    if ($l -notmatch '^\s*\|') { continue }
    $f = $l.Trim().Trim('|').Split('|')
    if ($f.Count -lt 6) { continue }
    $r = [pscustomobject]@{
        Name  = $f[0].Trim()
        Type  = $f[1].Trim()
        Owner = $f[2].Trim()
        Cost  = $f[3].Trim()
        Eff   = $f[4].Trim()
        Src   = $f[5].Trim()
    }
    if ($r.Eff -eq '效果要点' -or $r.Name -eq '名称') { continue }
    if ($r.Cost -match '^-+') { continue }
    [void]$cards.Add($r)
}

function Normalize([string]$s) {
    if ($null -eq $s) { return '' }
    $t = $s.ToLowerInvariant()
    $t = $t -replace '[\s\!\?\!\.\,\:\;\(\)（）「」【】]', ''
    return $t
}

# Aliases are GAME DATA: which English word / pinyin / shorthand means which card. They used to
# live here as a hashtable of this one game's card names (an open-source toolkit carrying one
# campaign's vocabulary - and a new mod could only be taught by editing code). The file is
#     cache\<game>_alias.json      {"hex": ["厄运缠身", "厄运缠身 II"], "bow": ["长弓", "弓"], ...}
# A missing or broken file is NOT fatal: matching degrades to plain text, and the hint is printed
# only when a query FAILS (so the common path stays 1~3 lines and costs no extra tokens).
$alias = @{}
$aliasNote = ''
if ($AliasFile -ne '' -and (Test-Path -LiteralPath $AliasFile)) {
    try {
        $json = [System.IO.File]::ReadAllText($AliasFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) {
            $terms = @(); foreach ($t in @($p.Value)) { if ("$t" -ne '') { $terms += "$t" } }
            if ($terms.Count -gt 0) { $alias[$p.Name.ToLowerInvariant()] = $terms }
        }
    } catch { $aliasNote = ("alias file unreadable ({0}) - matching card text only" -f (Split-Path $AliasFile -Leaf)) }
} else {
    $aliasNote = if ($AliasFile -eq '') { 'no alias file for this game (no current game)' }
                 else { ("no alias file: {0}" -f (Split-Path $AliasFile -Leaf)) }
}

$qn = Normalize $Q
$qnRaw = $Q.Trim().ToLowerInvariant()
$terms = @($qn)
if ($alias.ContainsKey($qnRaw)) { $terms += ($alias[$qnRaw] | ForEach-Object { Normalize $_ }) }

$scored = foreach ($c in $cards) {
    $nn = Normalize $c.Name
    $score = 0
    foreach ($t in $terms) {
        if ([string]::IsNullOrEmpty($t)) { continue }
        if ($nn -eq $t) { $score = [Math]::Max($score, 100) }
        elseif ($nn.StartsWith($t)) { $score = [Math]::Max($score, 70) }
        elseif ($nn.Contains($t)) { $score = [Math]::Max($score, 55) }
        elseif ($t.Length -ge 2 -and $t.Contains($nn)) { $score = [Math]::Max($score, 40) }
        else {
            # 逐字重合度（模糊）
            $hit = 0
            foreach ($ch in $t.ToCharArray()) { if ($nn.Contains([string]$ch)) { $hit++ } }
            if ($hit -gt 0 -and $t.Length -gt 0) {
                $ratio = $hit / [double]$t.Length
                if ($nn.Length -le $t.Length + 2 -or $ratio -ge 0.8) {
                    $score = [Math]::Max($score, [int](20 * $ratio))
                }
            }
        }
    }
    if ($score -gt 0) { [pscustomobject]@{ Card = $c; Score = $score } }
}

$hits = @($scored | Sort-Object -Property @{Expression = 'Score'; Descending = $true}, @{Expression = { $_.Card.Name.Length }; Descending = $false })
$top = @($hits | Select-Object -First $Max)

function Fmt($c) {
    $where = if ($c.Owner -and $c.Owner -ne '—') { "$($c.Type)/$($c.Owner)" } else { $c.Type }
    $cost = if ($c.Cost) { $c.Cost } else { '未确认' }
    $eff = $c.Eff
    if (-not $Full -and $eff.Length -gt 420) { $eff = $eff.Substring(0, 417) + '...' }
    return @(
        "【$($c.Name)】$where",
        "消耗/骰型：$cost",
        "效果：$eff",
        "来源：$($c.Src)"
    )
}

if ($top.Count -eq 0) {
    Write-Output "NOT FOUND:  '$Q'  —— 文本库($($cards.Count) 条) 里没有匹配，且不做推测。"
    if ($aliasNote -ne '') { Write-Output ("  hint: {0}；建它可让英文/简写也能查到。" -f $aliasNote) }
    # Closest candidates, ranked by the SAME character overlap the scorer uses. This used to be a
    # hardcoded list of four of this game's card names - the last piece of game data in this script,
    # and the reason a new mod's "did you mean" list showed somebody else's cards.
    $near = @($cards | ForEach-Object {
            $nn = Normalize $_.Name
            $hit = 0
            if ($qn.Length -gt 0) { foreach ($ch in $qn.ToCharArray()) { if ($nn.Contains([string]$ch)) { $hit++ } } }
            $ratio = 0.0; if ($qn.Length -gt 0) { $ratio = $hit / [double]$qn.Length }
            [pscustomobject]@{ Card = $_; Ratio = $ratio }
        } | Where-Object { $_.Ratio -gt 0 } |
        Sort-Object -Property @{ Expression = 'Ratio'; Descending = $true }, @{ Expression = { $_.Card.Name.Length }; Descending = $false } |
        Select-Object -First 3)
    if ($near.Count -gt 0) {
        Write-Output "最接近的候选（仅供参考，不是答案）："
        foreach ($n in $near) { Write-Output ("  - " + (Fmt $n.Card)[0]) }
    }
    exit 2
}

$i = 0
foreach ($h in $top) {
    $i++
    if ($top.Count -gt 1) { Write-Output "--- 匹配 $i/$($top.Count) (相关度 $($h.Score)) ---" }
    (Fmt $h.Card) | ForEach-Object { Write-Output $_ }
}
exit 0
