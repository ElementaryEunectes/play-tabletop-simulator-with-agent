# install_save2.ps1 - build TS_Save_5.json with UNIQUE tab ids.
#
# WHY: every tab in the current save has id=12. TTS identifies notebook tabs by
# that id, so with 13 identical ids getNotebookTabs() returns an unstable order
# (observed: the same tab was at position 1, then 4, then 2 on consecutive reads)
# and editNotebookTab always lands on the wrong tab. This gives each tab the id of
# its own key and a distinct title.
param(
    [string]$SavesDir = '',
    [string]$Root     = '',
    [string]$LuaFile  = '',
    [string]$SlotName = 'TS_Save_5.json',
    # 2026-10-07 新增：允许指定**任意**存档做底（默认仍是"最新 autosave"）；
    # 以及用 -KeepLua 把该存档里**原有的 Global 脚本保留**（拼在桥接脚本之前，避免弄坏模组自身逻辑）
    #   -SourceFile 'TS_Save_6.json' -KeepLua -SlotName 'TS_Save_7.json'
    [string]$SourceFile = '',
    [switch]$KeepLua,
    # 2026-10-07 新增：-KeepTabs —— **完整保留模组自带的笔记本页**，只**新增**一页「DSH 对话频道」。
    # 默认行为（不带这个开关）会把除最长那页以外的标题改成占位名 —— 那是给**某一局旧存档**定制的，
    # 装到别的模组上会污染它自己的说明页。通用模组请一律加 -KeepTabs。
    [switch]$KeepTabs,
    # 2026-10-07 新增：给烤好的存档换一个**有辨识度的显示名**（TTS 载入列表里看到的就是它）。
    # 中文名必须**走文件**（命令行参数过控制台代码页会乱码）：文件内容 = UTF-8 的一行名字。
    [string]$SaveNameFile = '',
    [int]$DryRun = 0
)
. (Join-Path $PSScriptRoot 'config.ps1')
if ($Root -eq '') { $Root = $WorkspaceRoot }
if ($SavesDir -eq '') { $SavesDir = $TtsSavesDir }
# Backfill AFTER config.ps1. Restored 2026-10-08: the incident had eaten this line, so the
# one script that is allowed to write a save read its Lua from an empty path.
if ($LuaFile -eq '') { $LuaFile = (Join-Path $DshTts 'lua\dsh_global.lua') }
$ErrorActionPreference = 'Stop'
$log = New-Object System.Collections.ArrayList
function L { param([string]$m) [void]$log.Add([string]$m) }
function Flush { $log | Set-Content -LiteralPath (Join-Path $DshTts 'docs\install2_log.txt') -Encoding UTF8 }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$TITLE_REAL = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0x44,0x53,0x48,0x20,0xE5,0xAF,0xB9,0xE8,0xAF,0x9D,0xE9,0xA2,0x91,0xE9,0x81,0x93))
function TitleJunk([int]$n) { return ("[x] spare page " + $n) }

try {
    L ('START ' + (Get-Date -Format 'HH:mm:ss'))
    Add-Type -AssemblyName System.Web.Extensions
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = [int]::MaxValue

    if ($SourceFile -ne '') {
        $srcPath = Join-Path $SavesDir $SourceFile
        if (-not (Test-Path $srcPath)) { throw ("source not found: " + $srcPath) }
        $src = (Get-Item $srcPath).FullName
    } else {
        $src = (Get-ChildItem $SavesDir -Filter 'TS_AutoSave*.json' | Sort-Object LastWriteTime -Descending)[0].FullName
    }
    L ('source: ' + (Split-Path $src -Leaf))
    $o = $ser.DeserializeObject([System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8))

    # 有辨识度的显示名（TTS 的 Save & Load 列表读的是 SaveName 这一项）
    if ($SaveNameFile -ne '') {
        if (-not (Test-Path $SaveNameFile)) { throw ('SaveNameFile not found: ' + $SaveNameFile) }
        $nm = ([System.IO.File]::ReadAllText($SaveNameFile, [System.Text.Encoding]::UTF8)).Trim()
        if ($nm -ne '') { $o['SaveName'] = $nm; L ('SaveName -> ' + $nm) }
    }

    $lua = [System.IO.File]::ReadAllText($LuaFile, [System.Text.Encoding]::UTF8)
    L ('lua chars = ' + $lua.Length)
    if ($lua -notmatch 'onExternalMessage') { throw 'lua lacks onExternalMessage' }
    if ($lua -notmatch 'DSH_VERSION') { throw 'lua lacks the version stamp' }
    # -KeepLua：保留底稿里模组自带的 Global 脚本（我的桥接脚本放**后面**，保证 onExternalMessage 是我的）
    $prevLua = ''
    if ($KeepLua -and $o.ContainsKey('LuaScript') -and $o['LuaScript']) { $prevLua = [string]$o['LuaScript'] }
    if ($prevLua -ne '') {
        L ('keep existing LuaScript chars = ' + $prevLua.Length)
        # ⚠️ IDEMPOTENCY (added 2026-10-09 after it actually happened): a save that was ALREADY baked
        # carries the bridge, and the player may have loaded it before we bake again - then the
        # source save's LuaScript already holds bridge #1, and -KeepLua would keep it and append
        # bridge #2. Result measured on a real save: DSH_VERSION assigned THREE times, bridge code
        # duplicated, the file doubled (2.9 MB vs 1.5 MB), and two onExternalMessage definitions
        # racing (last one wins - it "worked", which is the dangerous part).
        # So: cut any previous bridge out first and keep only the MODULE's own script. The bridge
        # starts at its own separator, which is also where __dsh_prev_onLoad was captured, so
        # everything before that line is the module's untouched script.
        $marker = "`n-- ===== DSH bridge (appended) =====`n"
        $cut = $prevLua.IndexOf($marker)
        if ($cut -ge 0) {
            L ('previous bridge found at ' + $cut + ' - stripped before appending the new one')
            $prevLua = $prevLua.Substring(0, $cut)
        }
        L ('module Lua kept chars = ' + $prevLua.Length)
        # ⚠️ 2026-10-07：Global 脚本槽只有一份，**后定义的 onLoad 会盖掉模组自己的 onLoad**。
        # 所以在桥接**之前**先抓住模组的 onLoad，桥接**之后再调用它** ⇒ 两边都能跑。
        $sep1 = "`n-- ===== DSH bridge (appended) =====`nlocal __dsh_prev_onLoad = onLoad`n"
        $sep2 = "`n-- ===== also run the module's own onLoad =====`nif type(__dsh_prev_onLoad) == 'function' then pcall(__dsh_prev_onLoad) end`n"
        $o['LuaScript'] = $prevLua + $sep1 + $lua + $sep2
    } else {
        $o['LuaScript'] = $lua
    }
    # Refuse to write a save that carries more than one bridge: count the version stamp (the module's
    # own v13 copy is stripped above, so anything above 1 here means the de-duplication failed).
    $stamps = ([regex]::Matches([string]$o['LuaScript'], 'DSH_VERSION\s*=\s*''')).Count
    L ('DSH_VERSION stamps in the result = ' + $stamps)
    if ($stamps -gt 1) { throw ('refusing to write: ' + $stamps + ' bridge copies in the save (de-duplication failed)') }
    $expectedLua = [string]$o['LuaScript']   # -KeepLua 时要比对**拼好的全文**，不能只比对桥接片段
    $o['XmlUI'] = ''

    # ---- conversation tab = the longest body --------------------------------
    # ⚠️ 2026-10-07：-KeepTabs（通用模组）路径**不需要**"已有的对话页" ——
    # 模组的存档可能一页笔记都没有（TabStates 为空 / 全是空 body），
    # 那种情况下"最长页"逻辑必然抛异常。所以这条检查只在旧路径上做。
    $keys = @($o['TabStates'].Keys) | Sort-Object { [int]$_ }
    $bestKey = $null; $bestLen = -1
    foreach ($k in $keys) {
        $b = [string]$o['TabStates'][$k]['body']
        if ($b.Length -gt $bestLen) { $bestLen = $b.Length; $bestKey = $k }
    }
    L ('tabs in source=' + $keys.Count + ' | longest body=' + $bestLen + ' (key=' + $bestKey + ')')
    if (-not $KeepTabs) {
        if ($bestLen -lt 100) { throw ('no conversation (longest ' + $bestLen + ')') }
    }

    # Re-key the tabs so ids are unique AND sequential from 0, which also makes the
    # game's list order match the keys. TabStates is a dict; rebuild it.
    if ($KeepTabs) {
        # ---- 通用模组路径（2026-10-07）: 原样保留模组自带的所有笔记本页，只**新增**一页对话频道 ----
        $newTabs = [ordered]@{}
        $maxId = -1
        $hasChan = $false
        foreach ($k in $keys) {
            $t = $o['TabStates'][$k]
            $newTabs[[string]$k] = $t
            if ($null -ne $t['id'] -and ([int]$t['id']) -gt $maxId) { $maxId = [int]$t['id'] }
            if ([string]$t['title'] -eq $TITLE_REAL) { $hasChan = $true }
        }
        if (-not $hasChan) {
            $nk = $keys.Count
            while ($newTabs.Contains([string]$nk)) { $nk++ }
            $newTabs[[string]$nk] = [ordered]@{
                title        = $TITLE_REAL
                body         = ''
                id           = ($maxId + 1)
                color        = 'Red'
                visibleColor = [ordered]@{ r = 1.0; g = 0.0; b = 0.0 }
            }
            L ('tabs(KEEP): added channel tab, key=' + $nk + ' id=' + ($maxId + 1))
        } else {
            L 'tabs(KEEP): module already has a DSH channel tab - left untouched'
        }
        $o['TabStates'] = $newTabs
        L ('tabs(KEEP): ' + $newTabs.Count + ' tabs preserved')
    } else {
    $newTabs = [ordered]@{}
    $newTabs['0'] = $o['TabStates'][$bestKey]
    $newTabs['0']['title'] = $TITLE_REAL
    $newTabs['0']['id'] = 0
    $newTabs['0']['color'] = 'Red'
    $newTabs['0']['visibleColor'] = [ordered]@{ r = 1.0; g = 0.0; b = 0.0 }
    $n = 0
    foreach ($k in $keys) {
        if ([string]$k -eq [string]$bestKey) { continue }
        $n++
        $t = $o['TabStates'][$k]
        $t['title'] = (TitleJunk $n)
        $t['body'] = ''
        $t['id'] = $n                       # unique id == its own key
        $t['color'] = 'Grey'
        $t['visibleColor'] = [ordered]@{ r = 0.5; g = 0.5; b = 0.5 }
        $newTabs[[string]$n] = $t
    }
    $o['TabStates'] = $newTabs
    L ('tabs: ' + $newTabs.Count + ' total, ids 0..' + $n + ' (unique)')
    }

    $out = $ser.Serialize($o)

    $chk = $ser.DeserializeObject($out)

    # ---- validation ---------------------------------------------------------
    if ([string]$chk['LuaScript'] -ne $expectedLua) { throw 'validation: lua mismatch' }
    $seen = @{}
    $dup = @()
    $marked = 0
    foreach ($k in @($chk['TabStates'].Keys)) {
        $t = $chk['TabStates'][$k]
        $idv = [string]$t['id']
        if ($seen.ContainsKey($idv)) { $dup += ($k + '=' + $idv) } else { $seen[$idv] = $true }
        if ([string]$t['title'] -eq $TITLE_REAL) { $marked++ }
    }
    if ($dup.Count -gt 0) { throw ('validation: duplicate ids -> ' + ($dup -join ',')) }
    if ($marked -ne 1) { throw ('validation: ' + $marked + ' marker tabs, need 1') }
    if (-not $KeepTabs) {
        if (([string]$chk['TabStates']['0']['body']).Length -lt 100) { throw 'validation: key 0 lost the conversation' }
    } else {
        L ('validation(KEEP): tabs kept = ' + @($chk['TabStates'].Keys).Count + ', marker tabs = ' + $marked)
    }
    L ('validated: ids unique=' + $seen.Count + ', marker tabs=1, conversation=' + ([string]$chk['TabStates']['0']['body']).Length)

    if ($DryRun -eq 1) { L 'DRY RUN'; L 'RESULT: OK'; Flush; exit 0 }

    # No saves_backup_* directory: TTS keeps three rolling TS_AutoSave*.json files
    # of its own, so this copy was pure duplication. It had accumulated 33
    # directories / 983 MB before being deleted, which is exactly the bloat the
    # workspace cleanup was meant to remove.
    $dst = Join-Path $SavesDir $SlotName
    [System.IO.File]::WriteAllText($dst, $out, $utf8)
    L ('wrote: ' + $dst + ' size=' + (Get-Item -LiteralPath $dst).Length)
    L 'RESULT: OK'
    Flush
    exit 0
}
catch {
    L ('EXCEPTION: ' + $_.Exception.Message)
    Flush
    exit 9
}