# bootstrap.ps1 - re-identify every key object on a FRESH save, so a new AI can take over.
#
# WHY THIS EXISTS
#   Everything in the handover docs that is a *guid* is bound to ONE save file. Open the
#   mod again and every guid changes. What does NOT change is the mod's own data:
#     * CustomDeck FaceURL hashes   (they come from the workshop assets)
#     * Nicknames that the mod itself sets (移动城市 / 哥伦比亚金券 / 初始干员 / 杂物箱 ...)
#     * Scales, and the left-to-right seat order
#   So identification is done by THOSE, never by remembered guids. Run this right after
#   obj_index.ps1 on a new save and it prints (and writes) the whole session map.
#
# USAGE
#   powershell -File '<本仓库>\tts\bootstrap.ps1'
#   -> prints a markdown table block AND writes cache\session_map.md
param(
    [string]$Index = '',
    [string]$Out   = ''
)
. (Join-Path $PSScriptRoot 'config.ps1')
# Backfills AFTER config.ps1 -- restored 2026-10-08. Without them the script exited
# "ERR no index" (or wrote to an empty path) no matter how it was called.
if ($Index -eq '') { $Index = (Join-Path $DshCache 'obj_index.csv') }
if ($Out   -eq '') { $Out   = (Join-Path $DshCache 'session_map.md') }

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Index)) { Write-Host ("ERR no index; run obj_index.ps1 first ({0})" -f $Index); exit 1 }
$rows = Import-Csv $Index
function H8($v) { $s = "$v"; if ($s.Length -ge 8) { return $s.Substring(0, 8) } else { return $s } }
function NUMSORT($g) { return @($g | Sort-Object { [double]$_.x }) }
$L = New-Object System.Collections.ArrayList
function Emit($line) { [void]$L.Add($line); Write-Host $line }

Emit ("# 本局物件对照（bootstrap.ps1 自动生成）")
Emit ("")
Emit ("> 存档索引：{0}（{1} 行）。**guid 只对这份存档有效**；换存档重跑本脚本。" -f (Split-Path $Index -Leaf), @($rows).Count)
Emit ("")

# --- 1. seats -------------------------------------------------------------------
Emit ("## 座位（桌上从左到右 = P4 / P3 / P2 / P1）")
Emit ("")
Emit ("| 列 | HandTrigger guid | x |")
Emit ("|---|---|---|")
# NOTE: this mod ships FIVE HandTrigger zones - four in the seat row and one stray at
# z = +114 (off-table). Sorting by x alone pulls the stray one into the middle of the
# seat order and silently shifts every player. Keep only the seat row.
$htAll = @($rows | Where-Object { $_.name -eq 'HandTrigger' })
$ht = @($htAll | Where-Object { [double]$_.z -lt -50 } | Sort-Object { [double]$_.x })
if ($ht.Count -ne 4) { Write-Host ("WARN HandTrigger in seat row = {0} (expected 4); total = {1}" -f $ht.Count, $htAll.Count) }
$seatNames = @('P4', 'P3', 'P2', 'P1')
$seatOf = @{}
for ($i = 0; $i -lt [math]::Min(4, $ht.Count); $i++) {
    Emit ("| **{0}** | `{1}` | {2:N2} |" -f $seatNames[$i], $ht[$i].guid, [double]$ht[$i].x)
    $seatOf[$seatNames[$i]] = $ht[$i].x
}
Emit ("")
Emit ("> `HandTrigger` 的数量与顺序就是座位数与列序；本 mod 是 **左→右 P4/P3/P2/P1**（P1 = 玩家）。")
Emit ("")

# --- 2. 金券计数器 ---------------------------------------------------------------
Emit ("## 哥伦比亚金券计数器（MrStump Universal Counter Token）")
Emit ("")
Emit ("| 列 | guid | x |")
Emit ("|---|---|---|")
$cash = NUMSORT @($rows | Where-Object { $_.nick -eq '哥伦比亚金券' })
for ($i = 0; $i -lt [math]::Min(4, $cash.Count); $i++) { Emit ("| {0} | `{1}` | {2:N2} |" -f $seatNames[$i], $cash[$i].guid, [double]$cash[$i].x) }
Emit ("")
Emit ("> 改数字用 `ds.ps1 -Do 'setCount:<guid>:<N>'`（只写 script_state **屏幕不动**，必须 setDescription + customSet）。")
Emit ("")

# --- 3. 资源计数器（三张固定图） -------------------------------------------------
$resMap = [ordered]@{ 'DB0D5A8C' = '源石'; 'A7224368' = '源岩'; 'DEBBB903' = '异铁' }
Emit ("## 资源计数器（Custom_Tile，按图 hash 认；每人一套三枚）")
Emit ("")
Emit ("| 资源 | 图 hash | P4 | P3 | P2 | P1 |")
Emit ("|---|---|---|---|---|---|")
foreach ($k in $resMap.Keys) {
    $grp = NUMSORT @($rows | Where-Object { (H8 $_.url) -eq $k })
    $cells = @()
    for ($i = 0; $i -lt 4; $i++) { if ($i -lt $grp.Count) { $cells += ("``" + $grp[$i].guid + "``") } else { $cells += '?' } }
    Emit ("| {0} | `{1}` | {2} |" -f $resMap[$k], $k, ($cells -join ' | '))
}
Emit ("")
Emit ("> 图标：**源石 = 深红星形晶体** · **源岩 = 金褐色石块堆** · **异铁 = 蓝灰金属晶体簇** · **金券 = 金条**。")
Emit ("")

# --- 4. 事件牌堆 -----------------------------------------------------------------
$deckMap = [ordered]@{ '46991FF2' = '绿色事件牌（6 张）'; '6BEBAEB4' = '黄色事件牌（10 张）'; '23A7DC5B' = '红色事件牌（6 张）' }
Emit ("## 事件牌堆（按牌堆里的图 hash 认）")
Emit ("")
Emit ("| 颜色 | deck guid | 位置 | 堆内张数 |")
Emit ("|---|---|---|---|")
foreach ($k in $deckMap.Keys) {
    $hit = $null
    foreach ($d in @($rows | Where-Object { $_.name -eq 'Deck' -or $_.name -eq 'DeckCustom' })) {
        $kids = @($rows | Where-Object { $_.parent -eq $d.guid })
        if (@($kids | Where-Object { (H8 $_.url) -eq $k }).Count -gt 0) { $hit = $d; break }
    }
    if ($hit) { Emit ("| {0} | `{1}` | ({2:N2}, {3:N2}) | {4} |" -f $deckMap[$k], $hit.guid, [double]$hit.x, [double]$hit.z, @($rows | Where-Object { $_.parent -eq $hit.guid }).Count) }
    else { Emit ("| {0} | ? | ? | ? |" -f $deckMap[$k]) }
}
Emit ("")
Emit ("> 抽牌：`ds.ps1 -Do 'draw:<deck>:<n>:<x>:<y>:<z>'`（默认面朝上）。**牌堆里的牌不是独立物件，`move:` 够不到。**")
Emit ("> 抽牌顺序 = 存档里该 Deck 的 `ContainedObjects` 顺序，`[0]` 是堆顶。")
Emit ("")

# --- 5. 移动城市 -----------------------------------------------------------------
Emit ("## 移动城市（Custom_Model，nick=移动城市）")
Emit ("")
Emit ("| guid | 位置 | 备注 |")
Emit ("|---|---|---|")
foreach ($c in NUMSORT @($rows | Where-Object { $_.name -eq 'Custom_Model' -and $_.nick -eq '移动城市' })) {
    Emit ("| `{0}` | ({1:N3}, {2:N3}) | 十字星 = 本坐标 − (2.6922, −1.8959) |" -f $c.guid, [double]$c.x, [double]$c.z)
}
Emit ("")
Emit ("> 归属靠**反投影成板面图素、裁图直读卡面编号**，**不要**按「离哪个停靠点近」猜。")
Emit ("")

# --- 6. 玩家版 / 城市面板 ---------------------------------------------------------
$pb = @($rows | Where-Object { $_.name -eq 'Custom_Token' -and [double]$_.sx -gt 5 } | Sort-Object { [double]$_.x })
Emit ("## 玩家版 / 城市面板（大号 Custom_Token）")
Emit ("")
Emit ("| 列 | guid | x | z | scale |")
Emit ("|---|---|---|---|---|")
for ($i = 0; $i -lt [math]::Min(4, $pb.Count); $i++) { Emit ("| {0} | `{1}` | {2:N2} | {3:N2} | {4} |" -f $seatNames[$i], $pb[$i].guid, [double]$pb[$i].x, [double]$pb[$i].z, $pb[$i].sx) }
Emit ("")
Emit ("> 判据：**scale 明显大**（本 mod ≈7.37）的 Custom_Token，且 x 与四个座位列对齐。")
Emit ("")

# --- 7. 分数记录标记 + 分数轨道 ---------------------------------------------------
Emit ("## 分数记录标记（BlockSquare，开局 4 枚叠在分数轨道「0」格）")
Emit ("")
$board = @($rows | Where-Object { $_.name -eq 'Custom_Board' -and [double]$_.sx -gt 2 })[0]
$sq = @($rows | Where-Object { $_.name -eq 'BlockSquare' -and $_.nick -eq '玩家标识物' -and $_.parent -eq '' })
if ($board -and $sq.Count -gt 0) {
    $bx = [double]$board.x; $bz = [double]$board.z
    $onmap = @($sq | Where-Object { [math]::Abs([double]$_.x - $bx) -lt 28 -and [math]::Abs([double]$_.z - $bz) -lt 28 })
    Emit ("| guid | x | y | z |")
    Emit ("|---|---|---|---|")
    foreach ($m in ($onmap | Sort-Object { [double]$_.y })) { Emit ("| `{0}` | {1:N2} | {2:N2} | {3:N2} |" -f $m.guid, [double]$m.x, [double]$m.y, [double]$m.z) }
    Emit ("")
    Emit ("> **4 枚叠在同一格 = 分数轨道「0」格，开局本来就该这样，不是摆错。** 颜色：红=P1 蓝=P2 绿=P3 黄=P4。")
    $sx = 0; $sz = 0
    if ($onmap.Count -gt 0) { $sx = [double]$onmap[0].x; $sz = [double]$onmap[0].z }
    Emit ("> **每 +1 分 = 世界 x + 1.68，z 不变**（单元格印 −1/0/1/2/3/4，每格 169~171 图素）。")
    Emit ("> ⇒ 分数 N 的标记位置 = `({0:N2} + 1.68*N, {1:N2})`。" -f $sx, $sz)
} else { Emit ("（没找到：需要 base board 与 BlockSquare|玩家标识物）") }
Emit ("")

# --- 8. 企业板 -------------------------------------------------------------------
$ent = @($rows | Where-Object { (H8 $_.url) -eq '480DBC07' })
Emit ("## 企业板（8 张共用一张 4x2 拼图，只有 CardID 区分）")
Emit ("")
Emit ("| guid | x | z |")
Emit ("|---|---|---|")
foreach ($e in NUMSORT $ent) { Emit ("| `{0}` | {1:N2} | {2:N2} |" -f $e.guid, [double]$e.x, [double]$e.z) }
Emit ("")
Emit ("> `CardID = deckId*100 + 格号`（左→右、上→下）；62500 罗德岛 · 62501 海德兄弟 · 62502 莱茵生命 ·")
Emit ("> 62503 富森银行 · 62504 雷神工业 · 62505 约翰老妈 · 62506 黑钢国际 · 62507 雷姆必拓。")
Emit ("> 查 CardID：``tts\guidinfo.ps1 -Guid <g1>,<g2>`。")
Emit ("")

# --- 9. 具名容器 -----------------------------------------------------------------
Emit ("## 快速查询表（权威速查，3 人地图板下方；按图 hash 认）")
Emit ("")
Emit ("| guid | hash | 位置 | 内容 |")
Emit ("|---|---|---|---|")
foreach ($qr in @(@('86AE9328','企业扩展图标与概念 + 操作说明'), @('525B6092','图标说明 + 核心概念及关键词'))) {
    $hit = @($rows | Where-Object { (H8 $_.url) -eq $qr[0] })
    foreach ($q in $hit) { Emit ("| ``{0}`` | ``{1}`` | ({2:N2}, {3:N2}) | {4} |" -f $q.guid, $qr[0], [double]$q.x, [double]$q.z, $qr[1]) }
}
Emit ("")
Emit ("> 内容已照录进 SOP §16。**这是除规则书外唯一权威的速查来源。**")
Emit ("")

Emit ("## 具名容器 / 特殊物（按 nick 认）")
Emit ("")
Emit ("| nick | guid | 位置 |")
Emit ("|---|---|---|")
foreach ($r in @($rows | Where-Object { $_.nick -ne '' -and $_.name -match 'Bag|Token|Tile|Deck' } | Sort-Object { [double]$_.x })) {
    Emit ("| {0} | `{1}` | ({2:N1}, {3:N1}) |" -f $r.nick, $r.guid, [double]$r.x, [double]$r.z)
}
Emit ("")

[System.IO.File]::WriteAllText($Out, (($L -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("`nwrote {0}  ({1} bytes)" -f $Out, (Get-Item $Out).Length)
