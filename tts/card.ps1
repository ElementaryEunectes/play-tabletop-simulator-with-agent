#Requires -Version 5.1
<#
  card.ps1 —— 王权骰铸「一条命令查牌」
  用法：  card.ps1 -Q '厄运缠身'      （也支持英文/模糊：-Q hex 、 -Q moon 、 -Q 长弓）
  数据源： cache\<game>_cards.md （初始化时建好的文本库；本脚本只读它，不联网、不裁图）
  输出：  1~3 行（名称 / 消耗·骰型 / 效果要点 / 来源）；查不到时输出 NOT FOUND + 最接近的 3 条候选。
  绝不编内容：查不到就说查不到。
#>
param(
    [Parameter(Position = 0)]
    [string]$Q = '',
    [int]$Max = 3,
    [switch]$Full
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# A missing -Q used to make PowerShell itself dump a multi-line mandatory-parameter error
# (~630 bytes of context for nothing). Answer it ourselves, in two lines.
if ([string]::IsNullOrWhiteSpace($Q)) {
    Write-Output "usage: card.ps1 -Q '<name or fragment>'   (data: cache\<game>_cards.md)"
    exit 2
}

# The card library is game data: WHICH file comes from tts\config.ps1 ($DshGameCards, derived from
# the GAME= line in local\games\_current.md). No game-specific filename in this script.
. (Join-Path $PSScriptRoot 'config.ps1')
$db = $DshGameCards
if ($db -eq '') { Write-Output 'NOT FOUND (no current game: set GAME= in local\games\_current.md)'; exit 1 }
$db = [System.IO.Path]::GetFullPath($db)
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

# 别名：英文/拼音/符号 都能查到对应中文牌
$alias = @{
    'hex'    = @('厄运缠身', '厄运缠身 II')
    'moonelf'= @('月精灵')
    'elf'    = @('月精灵')
    'bow'    = @('长弓', '弓')
    'witch'  = @('猩红女巫')
    'scarlet'= @('猩红女巫')
    'scar'   = @('猩红女巫')
    'moon'   = @('月精灵', '月光', '月之', '月影')
    'cp'     = @('老板大气', '黑暗冲击')
    'draw'   = @('加倍', '超级加倍')
    'block'  = @('下次一定', '打不到我')
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
    $near = @($cards | Where-Object { $_.Name -match '厄运缠身|魔法弹|长弓|月光' } | Select-Object -First 3)
    if ($near.Count -gt 0) {
        Write-Output "最接近的候选（仅供参考，不是答案）："
        foreach ($n in $near) { Write-Output ("  - " + (Fmt $n)[0]) }
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
