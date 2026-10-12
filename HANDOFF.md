# HANDOFF.md —— 交接简报（最近更新 **2026-10-11** · 回合交接已校准 · 文档已按"规则 / 代码"分家）

> **怎么读（按这个顺序）**：**§1 启动** → **§4 待办**（**发布前真正剩两条**：E（demo ＋ 30 秒录屏）与**冷启动验证**；**新登记一条**：第 9 条**外文 mod 机翻**）→ **§7.9 回合交接** → **§9 纪要**。
> 长期规矩 ⇒ `AGENTS.md`（本项目）＋ `$DSH_HOME\AGENTS.md`（平台宪章）；改东西前 ⇒ `tts\docs\MAINTENANCE.md`；坑 ×17 ＋ 注入 ⇒ harness home 的 `platform\MAINTENANCE.md`。
> **文档全索引 ⇒ `tts\docs\README.md`**；**本局状态 ⇒ `local\games\<游戏>\STATE.md`**（唯一真源：含"现在轮到谁"与续局步骤）。
> ⚠️ **先做 §1 的启动动作**（否则脚本会读写一个不存在的旧目录）＋ **每个新会话重建两个活件**（轮询器 ＋ file 哨兵，⇒ §4 第 3b 条）；**验证两件套** = 门禁 `tts\tests\run_all.ps1`（7 条）· 活体 `tts\tests\live_smoke.ps1`（17 条**只读**，需要 TTS）。
> 🪙 **省 token 纪律**（全文 ⇒ `AGENTS.md` 第 9 条）：**批量发命令**（⚠️ **例外：TTS 命令仍一条一发**）· **只 `grep` ＋ 切片读** · **搬运/审计交子代理** · **回复压到几行**。
> 🔌 **桥接**：**烤在存档里** ⇒ 换版本要重烤 ＋ 请玩家重载。盘上已成 **`v16-tracker-guid`**（`TS_Save_18.json`，显示名 = 该局游戏名 ＋ `-v16`）；**`TS_Save_17.json` 是上一档 `v15-tags-snap-hand`**（objs 都是 118）⇒ 判定**以 `tts\play.ps1 status` 返回为准**（⚠️ **端口 LISTENING ≠ API 可用**：2026-10-12 收工后现场核对时 39999 在监听、`status` 却报 **`BRIDGE DOWN`** ⇒ **盘上到底是哪一档仍未定音**，下次 TTS 正常时再读一次）；版本史 ＋ v16 的 guid 参数（**尚有未结的掉线嫌疑**）⇒ §9 / `VALIDATION.md` F14。

## 🔴 接手即做（2026-10-11 15:0x，本会话交接）

> **接手三步（照这个顺序）**：① 起 **hub**（`tts\tools\tts_hub.ps1`，**必须最先**，它独占 39998 ⇒ `MAINTENANCE.md` §5）；② 起 **轮询器**（`tts\tools\turn_poller.ps1`）；③ 挂 **file 哨兵**（`cache\turn_side.txt`，`^mine`，**`max_fires` 必须显式给**）。停轮询器：放 `cache\poller.stop`。⚠️ **三件都不跨会话**。
> **每回合的策略**：交还给他后 ⇒ **轮询一直开着等他**；他按 End Turn ⇒ 哨兵叫醒我 ⇒ ⛔ **先 `tts\tools\turn_side.ps1` 复核**（**"错位时要点两次"会造出假边沿**）⇒ 无对局动作时 `tts\tr.ps1 -To player` 交还 ⇒ 继续轮询。
> ⛔ **两条硬纪律**：**一次工具调用只发一条 TTS 命令**；**JSON 只在进程内构造**（⛔ 绝不交给 `powershell -File`，它吃引号 ⇒ 畸形信封 ⇒ TTS 收下不回复 ⇒ 39999 掉线，7 次实测 ⇒ `VALIDATION.md` **F14**）。
> **待办指针**：`cut`/`drop`/`paste`/`spawn:json` **四条都是死路**（后两条**会打挂 TTS**）⇒ 停止追查（⇒ `VALIDATION.md` F7/F10）· `hand:` 回显缺 `action` 已修（**要重烤 ＋ 重载**）· 门禁缺依赖已改报 **NOT RUN** · 冷启动与 **E（demo ＋ 录屏）** ⇒ §4。
> **台账指针**：hub 用法与坑 ⇒ `MAINTENANCE.md` **§5** · API 掉线根因与验收 ⇒ `VALIDATION.md` **F14 · L18 ✅ · L19 ✅** · 起链顺序 ⇒ `PLAY.md` 回合交接节 ＋ `BOOTSTRAP.md` §1 E。

## §1 启动（必做，30 秒）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <本仓库>\start-agent.ps1   # 只做 Set-Location 到本仓库
```
- 它**只切 cwd**（= 项目链注入的前提；不动 `$DSH_HOME`、不建 profile）；只要会话工作区 = 本仓库，直接 `dsh web` 也行。
- ⚠️ `$DSH_HOME` **双重含义**（harness home ＋ 本工作区根）：残留旧值 `<用户目录>\.dsh` ⇒ `tts\config.ps1` 解析到**已搬空的旧目录**（产物写丢、`live_index` 报 `ds.ps1 not found`）。
- 验证：`tts\play.ps1 status`（**版本号以实际返回为准**）· `tts\tests\run_all.ps1`。

## §2 对局状态 ⇒ **不在仓库里**

对局现状 · 续局步骤 · 已结清的规则 · 原始 guid · **待玩家拍板的规则冲突** · **卡面待补** ⇒ 全在 **`local\games\<游戏>\`**（`_current.md` 指向具体文件；`local\` 被 gitignore）。本仓库只放**对任何 TTS mod 都成立**的通用工具链（判据 ⇒ `AGENTS.md`）。

## §4 待办（按优先级）

> 🧭 **看这一行就够**：**发布前真正待办只有两条** —— ① 第 **4** 条里的 **E（demo ＋ 30 秒录屏）**；② 同条的 **冷启动验证**（clone 到新目录 ＋ 独立 `$DSH_HOME`，照 README 走一遍）。**③ 新登记、不急**：第 **9** 条的**外文桌游模组机翻**。
> 🔬 **冷启动验证：本沙箱内能做的部分已做完**：用 `git worktree add --detach` 做等价"干净检出"（沙箱里 `git clone` 报 `Win32 error 5`），**抓到真缺陷并已修（`bada9e2`）**：新检出里 `run_all.ps1` **7 条全挂**（门禁输出写 `cache\`，而该目录被 gitignore）⇒ 入口开跑前 `New-Item -Force` 建 `cache\` ＋ `out\`，复验 **6 PASS**（只剩 `bridge primitives (Lua)`，缺 `fengari`）⇒ 台账 ⇒ `tts\docs\VALIDATION.md`。⏳ **仍未做**：**真·第三方**在一台干净机器上跑一遍。
> 其余各条：**0 / 1 / 2 已结清** · **3 / 5 口径与收尾** · **3b 是"每个新会话要做的动作"** · **6 / 7 环境事实** · **8 已归档**。

0. ✅ **F8 已定案并修好（2026-10-09）**：四个原语活体上"名字是 nil"的根因 = **拼接进了 `setCount()` 函数体中间**（缺/多一个 `end` ⇒ 平衡 ⇒ 照编译照注册，名字却从没被赋值；**门禁全绿也看不见它**）⇒ 已修 `tts\lua\dsh_global.lua` ＋ 阴性对照 ＋ 门禁新增"整块加载"一步；活体验收（`TS_Save_11.json`）四种原语全好用。
   ⛔ **`spawn:type` 停止追查**（`spawnObject` 会卡死桥接线程、被 TTS 回滚）⇒ `tts\docs\VALIDATION.md` F10；⚠️ 那次探测**把 TTS 打挂了** ⇒ **一条一条探**。📌 桌上仍有**无引用的** `DSH-TURN`（`guid a7bf2e`）⇒ **可删**（⇒ F11）；顺带修好 `container:<guid>`（根因 = **`getObjects()` 返回纯 Lua 表、没有方法**，也是**卡库的来源**）。
1. ✅ **D2 已完成（2026-10-09）**：**对局型 mod** 的 `local\games\<游戏>\objects.json` 写好（8 个区块）⇒ `bootstrap.ps1` 可用（`cache\session_map.md` 92 行）。📌 **索引里同一物件常有两行** ⇒ 每块都要 `topLevel: true`；换局用 `bootstrap.ps1 -Inventory`（⇒ `BOOTSTRAP.md` §1b）；**`obj_index.ps1 -File` 要绝对路径**、教学写在 **Notecard** 上。
2. ✅ **重烤 ＋ 活体验收已完成（2026-10-11）**：`TS_Save_17.json` 上逐条真跑 —— `ping` = `v15-tags-snap-hand`（objs=118）· `players` ⇒ `ok count=2` · `take`/`destroy` 失败路径正常 · `spawn:copy` 正常 · `turn_tracker` 可用 · `container:` 可列牌（详见 §4 第 0 条）。
3. 🟡 **游戏侧**：本局（第二款 mod）的目的是**验证工具链** ⇒ 规则/座位/图卡**不必做**；✅ **卡库已建成**（`cache\<游戏>_cards.md`，**171 张**，`tts\card.ps1 -Q <牌名>`；生成器 **`tts\tools\cards_from_save.js`**（吃**存档**、文本完整；⛔ `build_cards.js` 是**活体**那条路、取不到牌堆内部的卡 ⇒ `MAINTENANCE.md` §5））⇒ 这一局**已无真待办**；真打时按 `local\games\<游戏>\FLOW.md` §5 问玩家。
3b. 🔴 **每个新会话要重建"活件"（最容易漏）**：**轮询器**（`tts\tools\turn_poller.ps1`，后台作业、不跨会话）＋ **file 哨兵**（`cache\turn_side.txt`，`pattern=^mine`，**必须显式 `max_fires`**）⇒ `tts\docs\PLAY.md` 回合交接节。
4. 🟡 **让第三方"简单部署 · 廉价游玩"的最后一块**：**E** demo ＋ 30 秒录屏（需 TTS）；✅ **A** `STATE`/`FLOW`/`MYHAND` 模板 ＋ **C** `tts\setup.ps1` 向导 **已完成**。判据：陌生人只有**公开仓库 ＋ Windows ＋ TTS ＋ 一个 workshop mod**，能否**一小时内**打完一回合（成本期望已写进 `README.md` / `README.en.md`）。🔴 **仍未做**：**冷启动验证**（clone 到新目录 ＋ 独立 `$DSH_HOME`，照 README 走一遍）；已做的部分与它抓到的真缺陷 ⇒ 本节顶部的 🔬。
5. 🟡 **开源收尾**：`LICENSE`(MIT) ✅ · `README.en.md` ✅ · 路径/隐私 ✅（树里 0 处 `C:\Users\<名字>`）· 离线门禁 **7 条** ✅ ⇒ 剩下"首次上手的时间/成本期望"写进 README 顶部。
6. ⚪ **平台层不随仓库走**（坑只在 harness home）⇒ 开源用户只有 `tts\docs\MAINTENANCE.md` §0；**"等玩家点结束回合"依赖 DSH 的 sentinel**，换 agent 平台会退化成轮询。
7. ⚪ **火绒**（环境事实，不是待办）⇒ `tts\docs\MAINTENANCE.md` §0。
8. ✅ **已归档（用户拍板）**：`read_turn.ps1`（批量替换事故的残骸 —— 运行期错，`check_ps1` 查不出来）· `front_watch.ps1`（某一局专用）· **`find_moved.js`（2026-10-12，0 引用的一次性调试件）** · **`tests\gen_bridge_alone.lua`（98 KB，F8 的一次性夹具；输入是 gitignored 且已不存在的 `local\scratch\running_global.lua` ⇒ **无法从受跟踪输入重建**、也没有陈旧性对拍）＋ `tools\scan_exec.js`（它唯一的读者）** —— 全部**移出仓库** ⇒ `~\.dsh\archive\tts-legacy\`（**逐件 SHA256 对拍一致**）；`cache\front.txt` 从此没有生产者；`gen_bridge_alone_test.js` **保留在树里**（工具，逻辑仍有参考价值）。台账 ⇒ `tts\docs\VALIDATION.md` F4/F8 · 清单 ⇒ `MAINTENANCE.md` §5「已归档」。

9. 🆕 **外文桌游模组的机翻 —— 省 token 优先（仓库主人 2026-10-12 登记）**：目标 = 把工坊里**英文/日文**桌游 mod 的**卡面文本或图**变成中文，让中文玩家直接能玩。
   - ⛔ **硬要求**：**不用大模型逐张翻**（那是 token 爆炸的正解反例）⇒ 判据写成可测的：**一副 30 张牌，翻译环节的 token ≈ 0**。
   - **先找现成**（候选已登记 ⇒ `tts\docs\PRIOR_ART.md` **§9**）：`tts-editor`（Node 版 External Editor API，与我们 `tts_api.ps1` 重叠最大）· `tts-toolkit` · **`tts-card-naming-tool`**（批量改存档卡名）· `ge_tts` · **`LibreTranslate`**（可自托管/离线 ⇒ "0 token"的关键件）· `cardocr` · `playwright-image-translator` · digiKam OCR。
   - **两条落地路，都挂在存档层（⛔ 不碰活体 TTS）**：① **改文本**（卡名／`GMNotes`／`Description` —— 存档能批量改、不动图，最省）；② **改图**（`CustomDeck.FaceURL` 换成本地生成的译图 ⇒ 要重烤存档；本仓 `install_save2.ps1` 就是**写存档的唯一通道**）。
   - **接口**：`obj_index.ps1`／`dump_lua.ps1`（读存档）＋ `install_save2.ps1`（写存档）⇒ 整链可离线跑。
   - ⏸ **实测不急**（主人 2026-10-12）：先用 `tts-editor` 交叉验证我们手写的客户端，再把 `LibreTranslate ＋ cardocr ＋ tts-card-naming-tool` 串成整链。

## §6 环境与坑 ⇒ 两处（本文件不复述）

- 本仓库要点（沙箱/HIPS/编码/门禁姿势）⇒ **`tts\docs\MAINTENANCE.md` §0**；平台 ×17 条坑 ＋ 上下文注入与隔离 ⇒ **`platform\MAINTENANCE.md`**（旧编号 §6.8/§6.9 = 那里的阳性对照两条）。
- **TTS 桌子本身的开销**（实测）：重桌子在**后台**仍烧 GPU（647 物件 ≈**73%** vs 空桌 ≈10%）⇒ 拖慢**整机输入**；修法 = 驱动「**后台应用程序最大帧速率**」20 fps，⚠️ **要重启 TTS 才套用**（73% → **11%**）。**用嘴代替手**：DSH 自带实验性语音输入 `@deepseek-ai/dsh-experimental-voice-input-bundle` ⇒ **`tts\docs\USER_GUIDE.md` §5**。

## §7.9 回合交接（**用桌上现成的 Turn Tracker ＋ 一次校准**）

**⭐ 最终结论（2026-10-10）**：回合信号**用玩家自己按的那个 Tracker**（社区件，**`Locked`、在存档里**），**不自己造任何物件**（⇒ `tts\docs\VALIDATION.md` F11）。

```powershell
tts\tools\turn_calib.ps1 -Discover              # 拍快照 → 请玩家按一次 End Turn → 唯一移动的那件 = 信号源
tts\tools\turn_calib.ps1 -Answer mine|player    # 同一次运行里读坐标＋记录"现在轮到谁"
tts\tools\turn_calib.ps1 -Show                  # 看校准档、证据、当前判定
tts\tools\turn_side.ps1                         # 运行时：mine | player | unknown | uncalibrated（哨兵用它）
```

- **唯一真源**：`cache\<game>_turn.json`（`tracker` guid · 两个落点 · 哪个 z 是"我" · **原始证据**）；**回合流水**记在 `local\games\<游戏>\STATE.md`，不另开计数器。
- **交还**：`tts\tr.ps1 -To player`（~0.9 s）。✅ **Tracker 自己是好的**（玩家实测）：按一下 ⇒ 颜色前进 ＋ 棋子挪到那位的手牌位置；⛔ 我早先"它用已删除的 `getPlayerHand()`"**是错的**（真因 = `Name` 字段为空）。
- ⛔ **我们改不了它的颜色**（四条路都不行：`callx` 弄挂 TTS · `messageID 3` 空环境 · 写 `script_state` 被 `onSave` 覆盖 · 改 `Name` 只管轮转范围）⇒ **位置是唯一判据，可能要点两次才换边**（玩家已接受）。全表 ⇒ `VALIDATION.md` F12/F13。
- ⚡ **快链**：`turn_poller.ps1` 2.5 s 一采 ＋ file 哨兵 inotify ⇒ **~0.5-3.3 s** 叫醒我（**平台投递另加 ~23 s，不在我们手里**）；⛔ 旧的 `command` 哨兵 **~20 s**，别用（⇒ `BOOTSTRAP.md` §2「哨兵的周期限制」）。
- ⛔ 判定错了 ⇒ **重跑 `-Discover` ＋ `-Answer`**，**不许**改代码里的数字或用坐标反推。

## §8 每请求注入（机制/预算/安装 ⇒ `tts\docs\INJECTION.md`）

平台宪章 **2,217** ＋ 项目 `AGENTS.md` **1,982** ＋ 本机 `AGENTS.local.md` **848** ＝ **5,047 B ≈ 4.93 KB/请求**（硬指标：**<5 KB**；此前 11.4 KB）。
瘦身原则：**只留"触发条件 ＋ 结论"**（例子与机制转指针 ⇒ `MAINTENANCE.md` §0 · `INJECTION.md` §4 · `USER_GUIDE.md`）；**凡"门禁已经守着"的判定，注入里不再复述**。
⚠️ 三条硬约束：`instruction hygiene` 会抓"**承载性指针被删**"（`start-agent.ps1`/`PLAY.md`/`local\games`/`tts\config.ps1`/`check_ps1.ps1` **必须留在项目层**）＋ 项目层 ≤3840 B ＋ 本机层 ≤4096 B；⚠️ 平台层**处处都注入** ⇒ 加条目前先问"它能不能落在项目文档里"，**加完重新量三份合计**。
发布时**先填那一行**（`start-agent.ps1` 里现在还是 `''`）：`$ProjectDshProfile`（或 `-DshProfile tts-agent`；⚠️ **不是** `dsh tts-agent web`）⇒ 全局槽清零后 ＝ 项目 ＋ overlay（**实测 = 2,830 B**）⇒ **`tts\docs\INJECTION.md` §4 方案 A′**。

## §9 会话纪要（理由在 git 提交信息里，只留结论）

- **⭐ 桥接版本史（只在换版本时读）**：v13 `turntoken`（已废）→ v14 `primitives`（`players` 座位权威 / `take` 点名取牌 / `spawn` copy / `destroy` / `player`）→ v15 `tags-snap-hand`（`container` ＋ `hand` 的 `holding`/`give`/`draw` ＋ `act` 的 tags/`setSnapPoints`/成员变量）→ **v16 `tracker-guid`（当前）**。⛔ **烤在存档里** ⇒ 不重烤＋不重载，新命令回 `no handler for cmd=…`；原语缺口 ⇒ **`VALIDATION.md` F6 · F2**。
- **⭐ 责任边界（2026-10-09 定，仍有效）**：我们**不做**"能照着打任何一款的控制层"（不存在）；交付 = **① TTS 原语的通用层** ＋ **② 用户低成本"教出"某一款控制层的规程**，判据 = **原语覆盖够不够 · 教一款快不快** ⇒ `play.ps1` 不可通用**不再是缺陷**（⇒ `VALIDATION.md` F1）；分层 ⇒ `tts\` 通用层 / `tts\play.ps1` 分发器 / `local\games\<游戏>\control\`（⇒ `BOOTSTRAP.md` §2b）。
- **⚠️ 开发坑（都踩过）**：`Player.takeObject` **不存在** ⇒ 摸牌走**物件侧** `deal`/`dealToColorWithOffset`；`ValueFromRemainingArguments` **吞掉位置动词**；dot-source **改写 `$PSCommandPath`**；Lua 是 **CRLF** ⇒ 按行处理**先 `.replace(/\r\n/g,"\n")`**；**"门禁全绿"只证明它检查了的东西**（⇒ `verify_f8.js` 第 2b 步 ＋ 阴性对照）。
- **⚠️ 两条硬规矩**：**同一时刻只有一个会话驱动桌面**；**动手前先 `git log`**（两个会话撞过同一个回合）。
- **归档 ＋ 历史（已结清）**：`read_turn.ps1` / `front_watch.ps1` ⇒ `~\.dsh\archive\tts-legacy\`（⇒ §4 第 8 条 ＋ `VALIDATION.md` F4）；新工具 `tts\tools\dump_lua.ps1`。更早各轮（脚本全修/BOM、认物数据离开代码、`TTS_WORKFLOW` 并入 `TTS_RULES`）⇒ git ＋ `tts\docs\`。

## §10 关键数字（2026-10-11 复测）

`tts\` 下 **45** 个 `.ps1` · 门禁 **7** 条（入口 `tts\tests\run_all.ps1`）· 注入 **5,047 B/请求**（`tts\doctor.ps1` 实测：项目 1,982 ＋ 全局 2,217 ＋ overlay 848；发布配置 ≈2,830 B）。
