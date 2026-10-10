# 冷启动 / 换局 / 换模组 —— **唯一一份**工作流（2026-10-07 合并）

> 以前分成两份（某一局的"换局流程" 与 `NEWMOD_DEPLOY.md` 的"异地部署"），
> **本质是同一件事**：让"我"在一个（可能陌生的）桌面状态里重新获得"能读 + 能操作"的能力。
> 所以合并成这一份，按**三种情形**走，前 4 步是**共同核心**。

## 情形判断
| 情形 | 特征 | 走法 |
|---|---|---|
| **A. 同一模组 · 接着上一局** | 桥接还在（`ping` 通）、只是新回合/新一天 | 直接 §1 的 C 步：读状态页开工 |
| **B. 同一模组 · 重开一局** | 桥接还在、要摆回开局 | §1 全流程（C 步用 `archive\tts-legacy\init.ps1` 重建认知） |
| **C. 换新模组（异地部署）** | 桥接不通（`ping` 无回执） | §1 全流程 + §2 的"带桥接进存档" |

---

## §1 共同核心：冷启动四步

**0. 这台机器准备好了吗**（新机器 / 新 clone 的**第一步**）
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tts\doctor.ps1     # 只读：PowerShell · 路径 · TTS 目录 · 39999 · node · 每请求注入字节
```
- 它列完现状后给 `VERDICT: ready` 或带修复建议的问题清单；**它启动不了也改不了任何东西**（纯只读）。
- TTS 目录 `MISSING` ⇒ 设 `$env:TTS_SAVES_DIR` / `$env:TTS_IMAGES_DIR`（见 `README.md` 的路径配置）。
- 它还会告诉你**每请求注入多少字节**（项目 `AGENTS.md` ＋ 本机 `AGENTS.local.md`；**全局槽应为 0**）。
- ⛔ **若全局槽不是 0** ⇒ 机器上存在 `$DSH_HOME\AGENTS.md`（那是"跨项目纪律"）：本项目建议**不放它** —— 全局槽零注入、且与启动方式无关。
- 📖 **机制 · 成本 · 安装时三份文件怎么放** ⇒ **`tts\docs\INJECTION.md`**（本步配套读；`tts\doctor.ps1` 可复核实测字节）。

**A. 让桌面有一个存档（只有情形 C 必须新存）**
- 玩家 `Menu → Save & Load → Save Game`，或挂机等自动存档（`TS_AutoSave*.json`，约 5 分钟）。
- ⚠️ 载入列表显示的是存档里的 **`SaveName`**，不是文件名（文件名是 TTS 编的槽位 TS_Save_N）。

**B. 确认桥接**（我 → TTS 的唯一通道 = 局内 Global 脚本 `tts\lua\dsh_global.lua`，收 `onExternalMessage` 回话）
```powershell
ds.ps1 -Do ping        # 期望 ok v=<DSH_VERSION> objs=<n> loads=<n>
```
- 版本号 = **"新桥接有没有真的进去"的唯一凭据**。`no reply` ⇒ 桥接不在（走 §2）。
- ⚠️ **用 `ds.ps1 -Do ping`，别用 `play.ps1 status`**（后者要先有该游戏的 `cache\<game>_rules.json`，否则连 TTS 都没碰就报 `NO PART`；理由见 `MAINTENANCE.md` §5 的「两层是怎么分开的」）。
- ⚠️ TTS 只接收、不吃合成输入 ⇒ 我**不能点按钮**；连「结束回合」都是玩家点。

**C. 盘点与重认**（guid 每局/每模组都变，**只认 hash + nick + scale + 坐标关系**）
```powershell
obj_index.ps1          # 存档侧全量（含 url hash / 容器）—— 滞后 ~5 分钟
live_index.ps1         # 实时全表（guid/name/x/z）
ds.ps1 -Do count       # 名称直方图
# 同一模组重开（某一局的专用旧入口，已归档）：archive\tts-legacy\init.ps1（面板核对 + 拼图 + cache\init_report.md）
```
- **顶层物件数 ≪ 真实件数**：组件多在 Bag/Deck 里 ⇒ `act:<guid>:getQuantity` / `read:<guid>` 深入看。
- 通用做法：**直接从存档 JSON 里读模组的脚本**（§2 D 步）。
- ⚠️ **状态袋是 TTS `Infinite_Bag`（无限袋）⇒ 取走 token 后 `getQuantity` 不会减少**，验证要看**物件总数**
  （`ping` 的 `objects` / `count` 的 `total`）。

**D. 更新状态页**（见 §3：一个游戏一份，别共用）

> ### ⚠️ 环境坑：`ERR TTS unreachable` 的两种情况（2026-10-07 实测）
> 1. **沙箱有时会掐掉「嵌套子进程」的网络**：`dsbatch.ps1` 内部还会再 spawn `ds.ps1` = **两层** ⇒ **整批**每条都
>    `ERR TTS unreachable`（约 2 秒超时）；而 **直接用 `ds.ps1`（一层）或"本进程内联发送"完全正常**。
> 2. ⇒ 看到 `ERR TTS unreachable`，**先探端口 39999 是否 OPEN**；OPEN 就说明是**沙箱网络/嵌套问题，不是 TTS 没开**，
>    换内联发送或直接调 `ds.ps1` 再试 —— **别再向玩家误报"TTS 没开"**。
> 3. ⇒ **绝不能用 `Get-Process` 判断"TTS 开没开"**：沙箱里只看得到十几个进程（连 `TabletopSimulator` 都看不见）。
>
> **内联发送最小骨架**（本进程内发 + 收，不 spawn 任何子进程）
> —— 协议表见 `tts_api.ps1` 文件头：**发包 `messageID` = 命令类型**（`2`=自定义消息 / `3`=对某物件执行 Lua，**选 3 时必须带 `guid`**）；
> **收包 `messageID` = 事件类型**（`1`=scriptStates `2`=print `3`=error **`4`=custom（命令层回包走这个）** `5`=returnValue `6`=saved `7`=objectCreated）。
> ⚠️ **TTS 会主动推无关事件** ⇒ **循环读、只认 `messageID == 4` 的包**，别把 `5`/`6` 当成回包。
> 📖 **完整表（含方向，以及"`5` 是 ExecuteLua 的返回值、**不是**载入"这处更正）**：`PRIOR_ART.md §3.2`。
> ```powershell
> $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 39998); $l.Start()
> $c = [System.Net.Sockets.TcpClient]::new(); $c.Connect('127.0.0.1', 39999)
> $cmd = '{"messageID":2,"script":"ping()"}'    # 2=自定义消息（改成 3 + "guid":"<g>" 就是对某物件执行 Lua）
> $b = [Text.Encoding]::UTF8.GetBytes($cmd)
> $c.GetStream().Write($b, 0, $b.Length); $c.GetStream().Flush()
> $c.ReceiveTimeout = 3000
> $buf = New-Object byte[] 8192
> try {
>   do {                                                            # 循环读直到拿到 messageID == 4 的回包
>     $n = $c.GetStream().Read($buf, 0, $buf.Length)
>     $s = [Text.Encoding]::UTF8.GetString($buf, 0, $n)
>   } while ($s -notmatch '"messageID"\s*:\s*4')
>   $s
> } catch { 'ERR no reply' }
> $c.Close(); $l.Stop()
> ```

**D. 唤醒机制（每个游戏都要重新确认）**
- **通用（跨游戏都成立）**：`channel_watch.ps1 -IntervalMs 5000` 轮询**笔记本对话页**（`tabread`），
  把状态写进 `cache\chan.txt`，格式 `<TAG> <chars> <时间> | <尾部内容>`；**TAG 见下**。
  配 **file 哨兵**（pattern `^NEW \d`）⇒ **玩家在笔记本里写字就能叫醒我**。
  - `NEW` = 尾部内容变了（**按内容判，不是按字数** —— 旧版只看字数增长，我发言裁剪笔记本后玩家再写就永不触发，2026-10-05 已修）
  - `INIT` = 本轮第一次读；`SAME` = 没变；`ERR-<原因>` = 没读到，原因已内联（见下）
  - ⚠️ `channel_watch.ps1` **不再 spawn `ds.ps1`**（2026-10-07 改）：它是后台作业 ⇒ 再 spawn 就是**两层**嵌套子进程
    ⇒ 沙箱掐网络 ⇒ **整个监听静默失效**。现在它 **dot-source `ttslib.ps1` 在自身进程内直接 TCP**（与 `ttsx.ps1` 同一份代码）。
- **某一局专用（换游戏即失效，别指望）**：`front_watch.ps1` 写 `cache\front.txt` = 前台状态 + `TURN=Pn`
  （靠**读 TTS 横幅的颜色方块**判断轮到谁）—— 那是**那一局 mod 自己画的横幅**。没有该横幅的 mod，这个文件永远出不了 `TURN=`。
- **换游戏后必做三步**：① 确认新存档里有**对话笔记本页**（没有就用 `install_save2.ps1` 的 `-KeepTabs` 加一页
  「DSH 对话频道」）；② **重启 `channel_watch`**（旧进程还指着旧存档/已退出）；③ 确认 **file 哨兵还注册着**
  （pattern `^NEW \d`，指向 `cache\chan.txt`）——哨兵不跨会话持久，**每次开工重新注册**。
- ⚠️ 换游戏后**先跑一次 `ttsx.ps1 -Cmd '{"cmd":"tabread"}'`** 手工确认笔记本读得到，再去信哨兵。

---

## §1b 认物数据：`local\games\<游戏>\objects.json`（`bootstrap.ps1` 的输入）

> **这是数据、不是代码**：哪个图 hash 是"源石"只对一款 mod 成立 ⇒ `bootstrap.ps1` 里**一个牌名/图 hash 都没有**；缺文件它**报错并指出路径**（不打空表冒充答案）。它只留通用识别方式：name / nick / 图 hash / 缩放 / 与参照物的距离。

**怎么产出它**（新 mod 的"教一次"）：先 `obj_index.ps1`，再
`powershell -NoProfile -ExecutionPolicy Bypass -File tts\bootstrap.ps1 -Inventory` ⇒ `cache\obj_inventory.md`（**name / nick / 图 hash 三个直方图**，是写这份文件的原料；`-Inventory` 本身**不需要** `objects.json`）。照直方图填下表，再跑不带 `-Inventory` 的 `bootstrap.ps1`。

**最小可用**（只有座位）：
```json
{ "seats": { "name": "HandTrigger", "zBelow": -50, "labels": ["P4","P3","P2","P1"], "player": "P1" } }
```

**顶层键**：`seats.name`（座位区物件的 `name`，TTS 通用 `HandTrigger`）· `seats.zBelow`（只留 `z` 更小的，**用来排除桌外多余的 zone**；不写就全留）· `seats.labels`（从左到右，按 x 升序）· `seats.player`（哪个是我，只影响一句提示）· `seats.note`（座位表后的 markdown，字符串或数组）· `sections[]`（每项一个区块，见下）。

**`where`（选物件，多个条件是 AND）**：`name` · `nameRegex` · `nick` · `nickRegex` · `nickNonEmpty`(true) · `topLevel`(true＝父为空 —— ⭐ **存档索引里同一物件常有两行**：顶层那行是权威坐标，容器里那份是副本；`obj_index.csv` 里副本占 1523/1659 ⇒ **几乎每个区块都该加它**) · `urlHash`(url 前 8 位十六进制) · `minScale`(`sx` 下限)

**`kind`**

| kind | 渲染成 | 附加键 |
|---|---|---|
| `seatRow` | 每人一行（计数器/玩家指示物/面板） | `where` · `sort` · `columns`（含 `scale` 就多一列） |
| `seatGrid` | 每个图 hash 一行、每人一列（每人一套的资源） | `where` · `byHash`（`{"AAAA1111":"矿石"}`） |
| `rows` | 满足 `where` 的普通表 | `columns`（`guid`/`pos`/`x`/`y`/`z`/`scale`/`nick`/`name`）· `sort` |
| `deckByHash` | 按**牌堆里那张牌的图 hash** 找 Deck（牌不是独立物件） | `byHash` |
| `nearRef` | 参照物附近的标记（如分数轨上的标记） | `where`(标记) · `ref`(参照物，取**最大**的一个) · `within` · `sort` · `stepPerUnit` ＋ `stepAxis` |

其余键：`title`（区块标题，markdown 原样）· `note`（标题后的 markdown）· `sort` = `x`/`z`/`y`/`size`。

**契约（`tts\tests\test_game_data.ps1` 钉死）**：`objects.json` 只放**某款游戏专属**的东西，通用渲染留在代码里。门禁用**假游戏** fixture 验两边 —— 关键是**否定**那条：换成"只有座位"的最小版 ⇒ 专属区块**必须消失**（"数据不在代码里"只有这个能证）。
⚠️ 那是**契约门禁**（离线、每次提交都跑），**不是"任何 mod 都成立"的验证**：后者要拿**一款真 mod** 照 §2 走一遍"教一款新 mod"，别造一款假游戏充数。

---

## §2 只有"换新模组"才需要的三步

> 🧭 **不知道从哪开始就先跑 `tts\setup.ps1`**（默认**只读**：打印"到第一回合"的 8 步 ＋ 转给 `tts\doctor.ps1` 体检）。
> **建这一局的骨架**用 `tts\setup.ps1 -InitGame <slug>` —— 它从 `tts\templates\`（`STATE` / `FLOW` / `MYHAND`）生成
> `local\games\<slug>\`，并把 `_current.md` 的 `GAME=` 指过去（**先备份**）；加 `-DryRun 1` 只预览。⛔ 别手抄模板 —— 漏一个文件后面会踩空。

**A. 把桥接烤进存档**（我；写 TTS 存档目录在工作区之外 ⇒ **会弹一次批准/提权**）
```powershell
& powershell -NoProfile -ExecutionPolicy Bypass -File '<本仓库>\tts\install_save2.ps1' `
    -SourceFile 'TS_Save_6.json' `      # 不填 = 最新 TS_AutoSave*.json
    -KeepLua `                          # 保留模组自带 Global 脚本，桥接拼在其后
    -KeepTabs `                         # 完整保留模组笔记本页，只新增一页「DSH 对话频道」
    -SaveNameFile '<本仓库>\cache\save_name.txt' `   # UTF-8 一行 = 载入列表显示名
    -SlotName 'TS_Save_7.json'
```
- 三个必踩的坑（已修，别再踩）：① 模组笔记页 body 全空 ⇒ 旧"找最长页当对话频道"逻辑会抛异常；
  ② **Global 槽只有一份，后定义的 `onLoad` 会盖掉模组自己的**（安装器已用 shim：桥接前抓住、桥接后再调）；
  ③ **中文名必须走文件**（命令行参数过控制台代码页会乱码）。
- 改完 `.ps1` 必跑 `check_ps1.ps1`；改 `.lua` 必跑 `node tts\validate_lua.js` **并改 `DSH_VERSION`**。
- 玩家载入烤好的存档 → 回到 §1 B 验版本号。

**C. 校准"轮到谁"（每款 mod 一次，2 分钟）** —— ⭐ **座位/手牌区坐标每款 mod 都不同，这件事没有通用解，必须初始化一次。**

```powershell
# ① 发现信号：脚本拍快照 → 提示玩家按一次 End Turn → 再拍 → 唯一移动的那件就是它
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\turn_calib.ps1 -Discover
# ② 记录归属：READ THE PIECE FIRST, then answer for THAT moment
powershell ... -File tts\tools\turn_calib.ps1 -Answer mine      # 现在轮到 agent（我）
powershell ... -File tts\tools\turn_calib.ps1 -Answer player    # 现在轮到玩家
# ③ 任何时候查：显示存档 + 现在的判定
powershell ... -File tts\tools\turn_calib.ps1 -Show
# 运行时读取（哨兵用的就是它）
powershell ... -File tts\tools\turn_side.ps1        # mine | player | unknown | uncalibrated
```

- **产物**：`cache\<game>_turn.json`（**唯一真源**）= `tracker` guid ＋ 两个落点坐标 ＋ **哪个 z 是"我"** ＋ **定这条的原始证据**（谁、什么时候、当时读数）。换 mod ⇒ 重跑 ① ②，**不改代码**。
- **三条防错设计**（都是为今天踩过的坑加的）：
  1. **同刻取样**：`-Answer` 在**同一次运行里**读坐标＋记录你的回答 ⇒ **杜绝"旧读数配新回答"**（我正是这样错了两次）；
  2. **拒绝猜**：`-Discover` 若看到**不是恰好一件**物件移动 ⇒ **拒绝写档**（避免把"多点了一下"记成信号）；
  3. **运行时宁可 unknown**：坐标飘出 `tolerance` 就回 `unknown`（哨兵不触发），**不猜**。
- ⛔ **绝不用坐标/屏幕方位/日志反推归属**；判定错了就**重跑 ①②**，不要手改数字（脚本头部与 `turn_side.ps1` 都写了这条）。

**⚠️ 哨兵的周期限制（2026-10-10 实测，别被它骗）**：

1. **探测有间隔** ⇒ **间隔内翻两次 = 看不见**（`player→mine→player` 只看到一次净变化）。判断"玩家按了几次"**不能只看日志**，要问玩家或看校准档的当前判定。
2. ⚡ **别把"间隔"当成只能压到 15 s —— 换机制更快**（2026-10-11 实测）：
   - **`command` 哨兵**：请求 15 s、平台实际 **~20 s** 一次（探测本身仅 0.8 s）⇒ 交接延迟最坏 **20 s**；**5 s 会被饿死**（试过：触发 1 次后不再推进）。
   - **`file` 哨兵（推荐）**：常驻作业 `tts\tools\turn_poller.ps1` **每 2.5 s** 读一次、**变化才写** `cache\turn_side.txt`，file 哨兵 inotify **<1 s** 触发 ⇒ 检测 **~0.5-3.3 s**（实测一次 **468 ms**）。
   - ⇒ 需要"快"就用 file ＋ 外部轮询器；需要"省事"才用 command 哨兵。**轮询器是后台作业、不跨会话**（重跑 ⇒ `PLAY.md` 回合交接节）。
   - ⚠️ 定完间隔**等 2~3 个周期核对时间戳**（改完就宣称"已加速"＝没验；也不能只看触发计数）。
3. **只有"翻转时"才报**（配 `pattern`）⇒ 稳态静默是**正常的**，不是哨兵死了。
4. **`sentinel` 要常驻进程**（`dsh web` 之类）才会探测与投递；一次性 headless 跑完就没人值守。
5. 触发消息里带的"便签"可能来自**已取消的旧订阅**（延迟投递）⇒ 先 `sentinel_list` 看**哪个 id 真的在跑**、触发计数几比几，再决定信不信那条便签。


**B. 读懂这个陌生模组**（三步）
1. **读脚本**：存档 JSON 里**每个物件都带 `LuaScript`**，主键 `LuaScript` = Global 脚本。
   用 `JavaScriptSerializer` 解析 → 递归 `ObjectStates` / `States[*].ObjectStates` / `ContainedObjects`
   → 打印带脚本的物件 + **它定义的所有 `function xxx(` 名字**。
2. **找入口**：从函数名/按钮 `click_function` 反推"玩家平时点哪儿"；预设坐标表（如 `blue_postable`）也在脚本里。
3. **没有 eval 也能"替玩家按按钮"**：这个 TTS 沙箱**没有 `eval`/`load`/`loadstring`**（桥接的 `run` 因此不可用），
   但 **External Editor API（端口 39999，回执在 39998）** 可以 ExecuteLua，且**代码跑在该物件的脚本环境里**
   ⇒ 能直接调用模组的按钮回调：
```powershell
tts_api.ps1 -Action exec -Guid <物件guid> -Lua "btnFn(getObjectFromGUID('<物件guid>'), 'Blue', false)"
```
- ⚠️ **无回执**（常报 NO REPLY）⇒ **必须用状态验证**（例：前后各读一次 `ping` 的 objs，看物件数是否增加；
  后面的 `objs 101 → 119`＝**举例，数值以当时实际为准**）。
- ⚠️ 与后台 `channel_watch` 抢 **39998** ⇒ 撞 "listener busy" 就重试。
- ⚠️ 需要 TTS 开着 **External Editor**（本机已开：`ds.ps1` 走的也是 39999）。

**C. 找规则书，只读"开局必需"的部分**（**新模组必做，别跳过**）
1. **先定位**：`find:规则` / `find:Rule` / `find:说明` / `find:手册`，或从 `count` 直方图里挑名字可疑的物件。
   （例：对局型 mod 桌上常有一本「规则书（中x.y英x.y版本）」，`0f4dfd` @ (190,−0.01)。）
2. **先判形态，再决定怎么读**（省 token 的关键）：
   - `Custom_Model`/`Custom_Tile` 贴图 ⇒ 用「附录A / `TTS_RULES.md` §5.2」的图素↔世界换算**裁图读**，只裁要用的区域；
   - `Deck`/`Bag`（一叠卡）⇒ `act:<guid>:getQuantity` 看几张，再决定逐张 `draw` 或按 hash 认；
   - 有纯文本（`getGMNotes`/`getDescription` 非空）⇒ 直接 `read`。
3. **只读"开局必需"的四件事**：① 起始 HP/CP（或等价资源）② 回合/阶段流程 ③ 胜负与终局条件 ④ 手牌/牌堆的初始设置。
   **其余（英雄 FAQ、细则、变体）等到真要用时再回去查**。
4. **抄进文件**：把 ①②③④ 写进该游戏的 `_FLOW.md`（规则常量）与 `<游戏>_STATE.md`（本局设置）——
   **以后不再重读规则书**，这本身就是最大的一笔节省。

⚠️ 规则书是**公开信息**（不是谁的手牌）⇒ 读它没有隐藏信息问题；但**读法要省**：先定位 → 先判形态 → 只读必需页。

---

## §2b 教出"控制层"：`local\games\<游戏>\control\`（**2026-10-09 新增**）

> **为什么不放仓库**：控制层里全是**这一款**的东西（座位名 · 计数板 · 骰盘 · 招式表） ⇒ 判据"换个 mod 还成立"
> 不成立 ⇒ 它属于 `local\`。仓库只提供**原语**与**入口**（`BOOTSTRAP.md` §2 走完 = 原语那半已就位）。

**要建什么**

```
local\games\<游戏>\
├── objects.json           # 认物数据（§1b，bootstrap.ps1 的输入）
├── STATE.md / FLOW.md     # 状态与规则（§3）
└── control\               # ⭐ 控制层：这一款专属，不进仓库
    ├── play.ps1           #   入口：自带 param()（动词/座位/开关），dot-source 下面几个
    ├── <名词>.ps1         #   按需拆分（如 dice.ps1 / rules.ps1 / verbs.ps1）
    └── ...                #   技能数据仍放 cache\<game>_rules.json（config.ps1 已给路径）
```

**入口契约（4 条，缺一条就接不上）**

1. **路径固定**：`local\games\<游戏>\control\play.ps1`（`tts\config.ps1` 解析成 `$DshGameControl`，`GAME=` 决定是哪一款）。
2. **路径一律取自 config，不写死仓库路径**：`$DshGameRules`（`cache\<game>_rules.json`）· `$DshLibTtslib`（`tts\ttslib.ps1`）·
   `$DshLibBridge`（`tts\lib\bridge.ps1`）· 入口还会传 `$DshTtsDir`（`tts\` 目录）以备需要。
   加载顺序：**先 `$DshLibTtslib`（TCP 传输）→ 再 `$DshLibBridge`（回包校验）**；`bridge.ps1` 依赖 `Invoke-Tts`，
   也依赖你定义的 `Fail`/`Err-Code`，所以**先定义它们再 dot-source bridge**（照骰铸那份的结构抄即可）。
3. **UTF-8 带 BOM**：⚠️ `local\` **不在** `check_ps1.ps1` 的扫描范围 ⇒ 没人替你补 BOM；没有 BOM 时 PS 5.1 按 ANSI 读，
   **中文招式名会变乱码**（自检静默失效）。参考实现里有一条**入口自检**会直接报 `NO PART`，抄它。
   ⚠️ 自检要用**在 dot-source 之前捕获**的路径：dot-source 会把 `$PSCommandPath` 改成被加载模块的路径。
4. **写操作默认只读**：改动桌面的动词必须要求显式开关（`-Apply` / `-Roll`），且支持 `-WhatIf`；**真写后自己回读**，
   不一致就报 `BAD DATA`（别把"发了命令"当成"生效了"）。

**怎么设计动词（一条命令一个阶段）**：照 `PLAY.md` 与 `tts\docs\USER_GUIDE.md` 的期望形状 ——
`turn`（**回合开局一条命令**：盘面 ＋ 我这边的关键资源 ＋ 可打招式 ＋ 笔记本尾条，**全只读**）·
`status` · 该游戏的资源增减 · 掷骰/翻牌 · 结算 · `say`（往笔记本发一行）。
**先只做"开局必需四件事"能跑起来的那几个动词**，别一次做全 —— 规则没读到的部分做了也是错的。

**验证（离线优先）**：控制层里带一个 `-SelfTest`（**不碰 TTS**）：用写死的用例核对招式名/骰面映射与
`cache\<game>_rules.json` 一致 ⇒ 改中文或改数据后能立刻发现漂移。跑法：`tts\play.ps1 -SelfTest`。

## §2c 接手一款没见过的新 mod：**标准开局**（8 步）

> **什么时候读我**：`ping` 通了、要在这款 mod 上真正开工的时候 —— §2 解决"怎么让它通"，本节是**通了的施工顺序**。
> ⚠️ **写入前必须先过 sanity check**（坐标范围 ＋ typed 标量）⇒ `MAINTENANCE.md` §7：这一步曾把一个模型送到物理引擎手里销毁。

```
1. ping / tabread                        → 确认连通 + 读玩家留言
2. obj_index.ps1 + bags_dump.ps1         → 全量物件表（本地 grep，别用 Lua 扫）
3. 找板子：getPosition/getRotation/getBounds → 记下中心、rotY、尺寸
4. ⭐ 坐标初始化：请玩家做一次校准动作（把棋子拖到明确参照点 → getPosition）
5. 认物：bootstrap.ps1 -Inventory → 写 local\games\<游戏>\objects.json → bootstrap.ps1 出地图
6. 算目标坐标 → move: → getPosition 回读   → 逐个确认落点
7. 写状态：setGMNotes / setScriptState     → 回读确认
8. say.ps1 汇报 + 请玩家确认                → 只问一次，别反复
```
（完整换 mod 流程 ⇒ §2 ＋ §2b"教出控制层"。）

---

## §3 状态页规范（**一个游戏一份，绝不共用**）
> 规则/边界全在 `AGENTS.md`（常驻宪章）；本节只讲**换局时怎么落状态页**。
- **`local\games\_current.md`** = 当前在玩哪一款 → 指向该游戏的状态页（**先读它**；`local\` 不进仓库）。
- 每款游戏一份 **`local\games\<游戏>\STATE.md`**（旧局归档在 `local\archive\` 下、以该局命名），内容=**只写"现在是什么"**：
  比分/资源/位置/**待办** + 本局 guid 对照。**规则、坐标、工具用法、纪律都不放这里**（规则→ 同目录 `FLOW.md`，纪律→`AGENTS.md`）。
- ⭐ **两层的命名规矩不一样，别搞混**：`local\games\<游戏>\` 下用**裸名**（`STATE.md`/`FLOW.md`/`MYHAND.md`/`objects.json` —— **目录就是命名空间**）；
  一局结束 ⇒ 归档到 `local\archive\`（**不进仓库**），而归档层是**平的** ⇒ 必须**加游戏名前缀**（`<GAME>_FLOW.md` · `<GAME>_STATE_final.md`），否则几局的文档互相撞概念。
  ⛔ 所以**搬进/搬出 `local\archive\` 时要改名**——这是唯一一处需要人工改名的地方。
- 归档动作本身：状态页重置或另开新的（旧局状态封存进上面那份带前缀的归档）。
- ⛔ **不要把 A 游戏的坐标/guid/规则写进 B 游戏的状态页**（某一局的"本局…"数据换模组即作废）。
- ⭐ **看 diff 一律走 `tts\diff_hidden.ps1 -Game <游戏>`**（隐藏区规则在 `cache\hidden_zones.csv`，换游戏只加一行）。
- ⛔ **STATE 同一时刻只允许一个写入者**（多子代理并发编辑会互相覆盖/留下过期行；改前先 read、改后回报字节数）。
- ⚠️ **改完任何 `.ps1` 都要跑 `tts\check_ps1.ps1`**（补 BOM ＋ 真解析器校验）；死脚本一律移进 `archive\tts-legacy\`，别留在 `tts\`。

## §4 跨模组都成立的铁律
> **全文在 `AGENTS.md` 的「⛔ 铁律」一节 —— 这里只留换局相关的三条，别在这儿抄一遍。**
1. 换模组后**上一局坐标/guid 全作废**，只保留"方法"（识别靠 hash + nick + scale + 坐标关系）。
2. 隐藏信息：对手隐藏区不读、**也不拿 guid 去对身份**（`diff_hidden.ps1` 已强制遮蔽）。
3. 中断过的工具调用 ≠ 没执行 ⇒ 重跑前先重读状态。

## §5 已知空白（待补，诚实清单）
- `exec` 的边界：已知对"带脚本的物件"有效；**无脚本物件 / 反复调用 / 并发**未验证。
- 桥接的 `callx`（带参数调用）**加了但未实测**（本次走的是 `exec`）。
- 部分模组的**规则书就在桌上**（如对局型 mod 的「规则书（中x.y英x.y版本）」物件）⇒ 新模组应先读它再开局。

## §6 新游戏初始化清单（可勾选）

> **什么时候读我**：换局 / 换模组时**照单走一遍**。
> 每条括号里给两个**已实测的实例**（`对局型` 2026-10-07 · `资源地图型` 2026-10-04），用来判断"这一步长什么样"。

**两份骨架**（新游戏起手：拷进 `local\games\<游戏>\` 再填 —— 骨架留在仓库，填好的不进）

`local\games\<游戏>\STATE.md`（**只写"现在是什么 + 待办"**）：
```markdown
# STATE.md —— <游戏名> · 对局状态（**唯一真源**）· ⛔ 不进仓库
> 规则/卡面/坐标 ⇒ 同目录 `FLOW.md`；手牌 ⇒ `MYHAND.md`；通用每回合动作 ⇒ 仓库 `tts\docs\PLAY.md`

## 当前
**<日期 + 一句话现状>**

| | HP | 资源 | 其他 |
|---|---|---|---|
| **我（<角色>）** | | | |
| **他（<角色>）** | | | |

## 续局 / 起手步骤
1. `tts\play.ps1 turn` 核盘面 → 与本表比对；**不一致由玩家拍，别自己复位**。（⚠️ 只在有该游戏 `cache\<game>_rules.json` 时可用；否则改用 `tts\ds.ps1 -Do ping` ＋ `live_index.ps1`）
2. 复述"轮到谁 + 待办"，**由他决定**；他每次宣告 **我必须表态"出牌 / 不出牌"**。
3. 重挂哨兵（命令见 `tts\docs\PLAY.md`）。

## 待办 · 本局固定事实（guid · 换局即作废：我/他 · 骰面（已验证）· 隐藏区边界（**不读**））
```

`local\games\<游戏>\FLOW.md`（**规则 · 卡面 · 坐标**；**读不到的不许编**）：
```markdown
# FLOW.md —— <游戏名> 的规则与卡面（⛔ 不进仓库）
> 只写**这款游戏专属**的东西；通用 TTS 规则 ⇒ 仓库 `tts\docs\TTS_RULES.md`。来源写清：桌上卡面 / 规则书 `cache\rulebook_*.pdf` / 玩家口述。

## 1. 开局必需四件事（**未确认的逐条列出，别猜**）：起始 HP/资源 · 回合流程 · 胜负条件 · 初始设置
## 2. 回合结构 · 3. 卡面/骰面/数值 · 4. 坐标与物件（认物数据在 `objects.json`，这里只写"什么意思"）
## 5. 未确认清单（⛔ **别自行合并冲突** —— 板面 vs 卡面不一致时交玩家拍板）
```

- [ ] **1. 有存档**（`Menu → Save & Load → Save Game`，或等 `TS_AutoSave*.json`）〔骰=`TS_Save_7.json`；城=`TS_Save_6.json`〕
- [ ] **2. 烤桥接**：`install_save2.ps1 -KeepLua -KeepTabs -SaveNameFile … -SlotName …`〔骰/城 同〕
- [ ] **3. `ping` 验版本**：回 `ok v=<DSH_VERSION> objs=<n> loads=<n>` ⇒ 桥接真进去了〔骰=`v12-callx`；城=旧版本号〕
- [ ] **4. 盘点**：`obj_index.ps1`（存档侧）+ `live_index.ps1`（实时）+ `ds.ps1 -Do count`（直方图）〔骰=顶层 **119** 件；城=跑 `init.ps1`〕
- [ ] **5. 读模组脚本**：存档 JSON 里每个物件都带 `LuaScript` ⇒ 拿 `function` 名 + 按钮 `click_function` + **预设坐标表**
      〔骰=`blue_postable`(14 摆位) + 英雄入口函数；城=城市面板/资源点脚本〕
- [ ] **6. 找规则书，只读开局必需四件事**（起始 HP/CP · 阶段流程 · 胜负条件 · 初始设置）
      ⚠️ **先判形态**：贴图 ⇒ 裁图；`Custom_PDF`/远端 ⇒ **读不了就直说，请玩家念**〔骰=远端 PDF，靠标准规则补；城=面板贴图〕
- [ ] **7. 找状态载体**（HP/资源到底存在哪）〔对局型=**`getScriptState.saved_count`**（`read`/`getGMNotes` 全空！）；
      资源地图型=资源计数器在 `GMNotes` + `call:plusOne`〕
- [ ] **8. 在桌上生成自己的座位**（**用模组自己的入口函数**，`-Exec <guid> -Lua "..."`，**靠物件数前后差验证**）
      〔对局型=`moon(getObjectFromGUID('<guid>'),'Blue',false)` ⇒ 101→119；资源地图型=自写的 `init` 链〕
- [ ] **9. 确认唤醒机制**（§1 D：`channel_watch` 起没起 · 对话页在不在 · 哨兵注册没有）〔骰=`cache\chan.txt`；
      城=`chan.txt` + `front_watch.ps1` 的 `TURN=Pn`〕
- [ ] **10. 定先手 → 第 1 回合**〔对局型=**未定**（FLOW §5 待确认）；资源地图型=按规则定〕
- [ ] **11.（收尾）写状态页**：`local\games\<游戏>\STATE.md` 只写"现在是什么"，规则进同目录 `FLOW.md`
      （⚠️ **若这一局已终局要归档**，才改成 `local\archive\<GAME>_*.md` 的**带前缀**命名 —— 见 §3）
