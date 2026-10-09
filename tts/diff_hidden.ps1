# diff_hidden.ps1 -- 通用「隐藏区折叠」的差异读取（跨游戏，规则外置）
#
# 为什么需要它
#   diff_index.ps1 的输出里必然带出每个变动物件的 guid / nick / 坐标，
#   其中就包含对手隐藏区（手牌/盖放）里的东西。看一眼就"脏"了：
#   2026-10-05 我拿 P1 盖放牌的 guid 对上了某张牌；2026-10-07 又在 diff 里
#   两次顺带看到隐藏区物件的 nick。=> **凡是要看 diff，都走这个脚本。**
#
# 与 diff_safe.ps1 的关系
#   diff_safe.ps1 是**已终局那一局**专用的（写死"x>=30 且 z<-30 那一列"），换局即作废。
#   本脚本把"隐藏区"外置成配置数据 cache\hidden_zones.csv，任何游戏都能用，
#   加一个游戏只需往里加一行，不用再写一个脚本。
#
# 判据（关键，别改）
#   * 坐标一律取**实时**索引 cache\live_index.csv（diff_index.ps1 每次都会先刷新它）；
#     ⛔ 绝不用 obj_index（那是存档，滞后 ~5 分钟，物件早动了）。
#   * 规则按文件顺序，**第一条命中即折叠**（多游戏规则并存时不会互相叠加）。
#   * ymin 非空时只折叠 y > ymin 的行：手牌区是"悬空"的，桌面上经过同一 x/z 范围的
#     公开物件（y 低）不能一起屏蔽。公开区（弃牌区/牌堆）靠 z 边界自然排除。
#   * 拿不准就**宁可折叠**：实时坐标查不到（多为 REMOVED）、y 未知、ymin 解析不了
#     => 一律按隐藏处理，并在输出里报告有多少项是这么判的。
#
# 用法
#   powershell -NoProfile -ExecutionPolicy Bypass -File diff_hidden.ps1 -Game <游戏>
#   diff_hidden.ps1 -Snapshot     # 透传：冻结基线（等价 diff_index.ps1 -Snapshot）
#   diff_hidden.ps1               # 不传 -Game => 所有规则都生效（第一条命中的生效）
param(
    [string]$Game = '',
    [string]$ZonesFile = '',
    [switch]$Snapshot
)
$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$cache = Join-Path $root '..\cache'
if (-not $ZonesFile) { $ZonesFile = Join-Path $cache 'hidden_zones.csv' }
$diff    = Join-Path $root 'diff_index.ps1'
$liveCsv = Join-Path $cache 'live_index.csv'

if ($Snapshot) {
    $snap = & $diff -Snapshot 6>&1
    foreach ($l in @($snap)) { Write-Host "$l" }
    exit 0
}

# ---------------------------------------------------------------- 规则匹配 ---
function Get-Norm([string]$s) {
    if (-not $s) { return '' }
    return ($s.ToLowerInvariant() -replace '[^a-z0-9]', '')
}
function Get-Lev([string]$a, [string]$b) {
    $n = $a.Length; $m = $b.Length
    if ($n -eq 0) { return $m }
    if ($m -eq 0) { return $n }
    $w = $m + 1
    $d = New-Object 'int[]' (($n + 1) * $w)
    for ($i = 0; $i -le $n; $i++) { $d[$i * $w] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[$j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        for ($j = 1; $j -le $m; $j++) {
            $c = 1; if ($a[$i - 1] -eq $b[$j - 1]) { $c = 0 }
            $v = $d[($i - 1) * $w + $j] + 1
            if (($d[$i * $w + $j - 1] + 1) -lt $v) { $v = $d[$i * $w + $j - 1] + 1 }
            if (($d[($i - 1) * $w + $j - 1] + $c) -lt $v) { $v = $d[($i - 1) * $w + $j - 1] + $c }
            $d[$i * $w + $j] = $v
        }
    }
    return $d[$n * $w + $m]
}
# 0=精确 1=前缀 2=包含 3=编辑距离<=2   99=不匹配
# 放宽到"模糊"是有意的：游戏名打错一个字母（dicethtrone）不该退化成"不过滤"。
function Get-GameScore([string]$want, [string]$have) {
    if (-not $want -or -not $have) { return 99 }
    if ($want -eq $have) { return 0 }
    if ($want.Length -ge 4) {
        if ($have.StartsWith($want) -or $want.StartsWith($have)) { return 1 }
        if ($have.Contains($want) -or $want.Contains($have))     { return 2 }
    }
    if ((Get-Lev $want $have) -le 2) { return 3 }
    return 99
}

if (-not (Test-Path -LiteralPath $ZonesFile)) { Write-Host ("ERR no zones file: {0}" -f $ZonesFile); exit 1 }
$tmpl = @(Import-Csv -LiteralPath $ZonesFile -Encoding UTF8)
$zones = New-Object System.Collections.ArrayList
foreach ($r in $tmpl) {
    $xm = 0.0; $xx = 0.0; $zm = 0.0; $zx = 0.0
    $ok = [double]::TryParse("$($r.xmin)".Trim(), [ref]$xm)
    if ($ok) { $ok = [double]::TryParse("$($r.xmax)".Trim(), [ref]$xx) }
    if ($ok) { $ok = [double]::TryParse("$($r.zmin)".Trim(), [ref]$zm) }
    if ($ok) { $ok = [double]::TryParse("$($r.zmax)".Trim(), [ref]$zx) }
    if (-not $ok) { Write-Host ("WARN 规则坐标无法解析，已跳过: game=[{0}] label=[{1}]" -f $r.game, $r.label); continue }
    [void]$zones.Add([pscustomobject]@{
        game = "$($r.game)"; label = "$($r.label)"
        xmin = $xm; xmax = $xx; zmin = $zm; zmax = $zx; ymin = "$($r.ymin)".Trim()
    })
}
if ($zones.Count -eq 0) { Write-Host ("ERR no usable rules in {0}" -f $ZonesFile); exit 1 }

$active = @($zones)
if ($Game) {
    $want = Get-Norm $Game
    $scored = foreach ($z in $zones) { [pscustomobject]@{ z = $z; s = (Get-GameScore $want (Get-Norm $z.game)) } }
    $minS = ($scored | Measure-Object -Property s -Minimum).Minimum
    if ($null -eq $minS -or $minS -ge 99) {
        $known = (($zones | ForEach-Object { $_.game } | Sort-Object -Unique) -join ', ')
        Write-Host ("ERR 未知游戏 '{0}'（不会静默不过滤）；已知: {1}" -f $Game, $known)
        exit 1
    }
    $active = @($scored | Where-Object { $_.s -eq $minS } | ForEach-Object { $_.z })
    if ($minS -gt 0) {
        Write-Host ("[隐藏区] -Game '{0}' 无精确匹配，按近似匹配使用 game={1}" -f `
            $Game, (($active | ForEach-Object { $_.game } | Sort-Object -Unique) -join ','))
    }
}
foreach ($z in $active) {
    $ys = ''
    if ($z.ymin -ne '') { $ys = (" y>{0}" -f $z.ymin) }
    Write-Host ("[隐藏区规则] {0} / {1}  x{2}..{3} z{4}..{5}{6}" -f `
        $z.game, $z.label, $z.xmin, $z.xmax, $z.zmin, $z.zmax, $ys)
}

# ---------------------------------------------------------------- 读实时坐标 ---
# diff_index.ps1 自己会先跑 live_index.ps1 刷新 cache\live_index.csv，所以这里
# 在读 diff 之后取用即可 —— 拿到的一定是"此刻"的坐标。
$live = @{}
if (Test-Path -LiteralPath $liveCsv) {
    foreach ($r in (Import-Csv -LiteralPath $liveCsv -Encoding UTF8)) { $live["$($r.guid)"] = $r }
}

$out = & $diff 6>&1
$hidden = 0
$noLive = 0
foreach ($line in @($out)) {
    $s = "$line"
    if ($s -match '^\s{2}([0-9a-fA-F]{6})\s') {
        $g = $Matches[1]
        $x = 0.0; $y = 0.0; $z = 0.0; $hasY = $false
        if ($live.ContainsKey($g)) {
            $row = $live[$g]
            [void][double]::TryParse("$($row.x)", [ref]$x)
            [void][double]::TryParse("$($row.y)", [ref]$y)
            [void][double]::TryParse("$($row.z)", [ref]$z)
            $hasY = $true
        } else {
            # 实时索引里没有 => 物件已不在桌上（多为 REMOVED）=> 退用行内坐标，y 视为未知
            $mm = [regex]::Match($s, 'x=(-?\d+(?:\.\d+)?)')
            if ($mm.Success) { [void][double]::TryParse($mm.Groups[1].Value, [ref]$x) }
            $mm = [regex]::Match($s, 'z=(-?\d+(?:\.\d+)?)')
            if ($mm.Success) { [void][double]::TryParse($mm.Groups[1].Value, [ref]$z) }
        }
        $hit = $false
        foreach ($zn in $active) {
            if ($x -lt $zn.xmin -or $x -gt $zn.xmax) { continue }
            if ($z -lt $zn.zmin -or $z -gt $zn.zmax) { continue }
            if ($zn.ymin -ne '') {
                if ($hasY -and ($y -le [double]$zn.ymin)) { continue }   # 公开的桌面物件，别误伤
            }
            $hit = $true
            break
        }
        if ($hit) { $hidden++; if (-not $hasY) { $noLive++ }; continue }
    }
    Write-Host $s
}
if ($noLive -gt 0) { Write-Host ("  [其中 {0} 项无实时坐标(y 未知) —— 按保守规则折叠]" -f $noLive) }
Write-Host ("  [隐藏区共 {0} 项 —— 按纪律不看内容]" -f $hidden)
