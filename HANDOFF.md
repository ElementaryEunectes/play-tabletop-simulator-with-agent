# HANDOFF.md —— 交接简报（2026-10-07 深夜收官）

> **谁读**：接手这个项目的下一个 agent（或几天后的我）。
> **怎么读**：本文件 = "现在到哪了 + 先干什么"；长期规矩在 `AGENTS.md`（本项目）与 `~/.dsh\AGENTS.md`（平台）；
> 每局开工照 `tts\docs\CURRENT.md` → `DICETHRONE_STATE.md` → `PLAY.md` 三步走。
> ⚠️ **先做 §1 的启动动作，否则所有脚本会读写一个不存在的旧目录。**

---

## §1 启动（必做，30 秒）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <本仓库>\start-agent.ps1
#   → 把 $env:DSH_HOME 钉到项目根，然后起 dsh web
```
**为什么**：`DSH_HOME` 双重含义（harness home ＋ 本项目工作区根）。环境里若残留旧值 `<用户目录>\.dsh`，
`tts\config.ps1` 会解析到**已被搬空的旧目录**，产物写丢、`live_index` 报 `ds.ps1 not found`。
**先验证**：`tts\play.ps1 status` 应回 `bridge=v12-callx` 且 `objs=136` 附近。

## §2 现在的状态

| | |
|---|---|
| 项目位置 | 本仓库根（= `$DSH_HOME`）· 独立 git 仓库 · **46 文件跟踪** |
| 旧目录 `.dsh` | **项目产物不在这里**（sessions/storages/profiles/attachments ＋ 平台 `AGENTS.md`），但 **`archive\` 还在**：`~\.dsh\archive\tts-legacy\`＝33 个旧 `.ps1` · `~\.dsh\archive\system\` |
| 游戏 | **《王权骰铸》对局挂起中**（2026-10-08 23:46 玩家说"结束游戏"），随时可续 |
| 盘面 | **我 26/4 · 他 40/4**（2026-10-08 结清并回读 ✅）· 物件 **136** · 桥接 `v12-callx` · 存档 `TS_Save_7.json`；细节以 `DICETHRONE_STATE.md` 的「当前」块为准 |
| 进度 | **R4 他的回合未收**（「厄运缠身」已结清：附加骰 🌀＋✳ ⇒ 8 伤、我 👣👣 防半 ⇒ 我 30→26；他 41→40）→ 他收尾后进 **R5（我的回合）** |
| 棋子状态 | 他 **爆裂 3/3（满）**；他该放 1 个「操控概率」token（厄运缠身的 ✳；`Infinite_Bag` 取出来的 token 没图案 ⇒ **摆放归他**） |
| 哨兵/watcher | **都已撤停**（续局时要重挂：file 哨兵盯 `cache\front.txt` 的 `TURN=P2`，以及 `cache\chan.txt` 的 `^NEW`） |

## §3 续局怎么走（照 `DICETHRONE_STATE.md` 的「恢复打法」）

1. `tts\play.ps1 status` 核盘面 → 与 STATE 不一致时**以 STATE 为准复位**（`ds.ps1 -Do setCount:<guid>:<n>`）；
2. 向玩家复述"轮到谁 ＋ 待办"，**由他决定**：① 重新宣告「厄运缠身」或改打别的 ② 放操控概率 token ③ 按「结束回合」；
3. **重挂哨兵** ＋ 确认 watcher 心跳（`cache\front.txt` 的 mtime 秒级滚动）；
   死了就用后台作业重启 `front_watch.ps1 -Minutes 600` / `channel_watch.ps1 -Minutes 600 -IntervalMs 12000`。

## §4 待办（按优先级）

1. ✅ **脚本已全部修完**（2026-10-08，提交 `96dba9f`）。原来只当"4 个语法坏脚本"，实际有**两层**：
   | 层 | 脚本 | 真相 |
   |---|---|---|
   | 语法 | `tts\diff_index.ps1` · `tts\card_index.ps1` | **只是丢了 BOM**（中文被当 ANSI 读 ⇒ 一堆假语法错）。**根因在 `check_ps1.ps1` 本身**，见 §6.8 |
   | 语法 | `tts\index_images.ps1` · `tts\tts_api.ps1` | 真被改写坏（`$`→`i`、`)` 被删、`'`→`C`、`J` 被吃；`@()`→`@(`；一处硬编码输出路径）。**逐行手工重写** |
   | 运行 | `tts\obj_index.ps1` · `tts\bags_dump.ps1` · `tts\install_save2.ps1` · `tts\bootstrap.ps1` · `tts\diff_index.ps1` | 少了"dot-source 之后回填默认路径"那行 ⇒ **解析 0 错误、一跑就写空路径**。已按 `SCRIPTS.md`/文档补回原文件名 |
   ⇒ 现在 28/28 通过真解析器。**下次动 `.ps1` 照旧**：逐个 `read` → 精确 `edit`（⛔ 不许批量字符串替换）→ `check_ps1.ps1` → `git commit`。
2. 🔴 **仍有 5 条规则冲突等玩家拍板**（板面 vs 卡面不一致，**别自行合并**）：
   `打不到我`（板面 👣👣 防半 ＋ 每 2🏹 反 1 ／ 卡面 II 箭+月 防 14 ＋ 1×🏹 反伤）·
   `长弓 III`（卡面 5/7/9 ／ 板面 4/5/7）· `致命魔法`（9 vs 2）· `爆炸射击`（骰型未读）· `星蚀`（月×4/×5）。
3. 🔴 **卡面文本待补**（读不到不许编）：我的 `噩梦(MOON 28)`、`终极：群星陨落(MOON 32)`；
   玩家**英雄板基础档**（魔法弹/诅咒弹/噩梦之爪/吸取/混乱冲击/黑暗冲击/心灵震撼/究极/绝对混沌/终极：混沌之怒）。
   ⇒ 最省事：**请他摊牌到桌上或贴图**（桥接读不到容器里的牌）。
4. 🟡 **开源准备**：`.gitignore` ✅ · 路径/隐私去硬编码 ✅（树里 `C:\Users\<名字>` **0 处**）· `README.md` ✅（状态已刷新）·
   4 个脚本修完 ✅ · **破坏性动词护栏** ✅（`roll.ps1` 明说意图 · `play.ps1 -Apply -WhatIf` ＋ 写完回读校验 · `install_save2 -DryRun`）·
   **英文 README** ✅（`README.en.md`）· **测试** ✅（`tts\tests\` 两个离线自测，且都做过阳性对照）· `validate_lua.js` 可移植 ✅。
   **还缺**：`LICENSE` —— 已选 **MIT**，**只等署名**（仓库 git 身份是 `DSH agent / agent@local`，不适合当版权行）。
   ⚠️ **真正 publish 之前还有一件必做**：`tts\docs\DICETHRONE_STATE.md`「我方手牌」与 `HANDOFF.md` §7 记着**对局中的隐藏信息**；
   这一局若还要继续，公开仓库就等于把我的牌摊给任何人看 ⇒ **发布前先删掉那两段**（或按 `PLAY.md` 的 ≤5KB 规则把细节挪进 gitignore 的 `tts\docs\archive\`）。
5. ✅ **`diff_index.ps1` 的离线自测已收进仓库**：`tts\tests\test_diff_index.ps1`（＋ `fake_live_index.ps1` 桩 ＋ `fixtures\*.csv`）
   与 `tts\tests\test_param_backfill.ps1`；`check_ps1.ps1` 已改**递归**，测试自身也受 BOM ＋ 真解析器校验。
   ⚠️ 改这两个测试**必须重跑阳性对照**（故意造一个坏探针看它是否真报错，见 §6.8/§6.9）。
6. ✅ **效率优化（2026-10-08）**：回合开局压成**一条命令** `play.ps1 turn`（实测 **1.5s**，替代 `status`+`roll`+`tabread` 的 ~2.9s）；
   `say.ps1` 改成**单进程就地 TCP**（**0.79s** vs ~1.7s）；`income` 补上写护栏（默认只读，见 §6.11）；
   项目 `AGENTS.md` **6432 → ~2100 字节**（这份**每次请求都在计费**，所以易变的「已知状态」全部推给 STATE/HANDOFF）；
   `PLAY.md` **4219 → ~2100**；新增 **`tts\docs\USER_GUIDE.md`**（人怎么用）。
   ⇒ **下一次开局的默认动作：`tts\play.ps1 turn`，别再 status+roll 各跑一次。**
   **为什么没动 Lua**：实测往返不是瓶颈 —— 一个 PowerShell 进程启动固定 **0.35s**，而一次 TTS 往返只 ~40ms
   （`play.ps1 turn` 17 次往返仍是 1.48s）。把 17 次并成 1 次大约省 0.6s，却要**重装存档 + 请玩家重载**（改 `dsh_global.lua` 的代价）
   ⇒ **不划算，别去做**，除非以后有一次性几十条 act 的新场景。
   **为什么 `AGENTS.md` 只砍到 2856**：剩下的是**不变量**（纪律/路径/启动）。易变的东西全在 STATE/HANDOFF —— 它们是**按需读**，
   而 AGENTS.md **每个请求都注入**。再往下砍就得把纪律搬进按需文档，代价是"新会话可能不读"。**平台那份 `~/.dsh\AGENTS.md`（3925 字节）现在是注入的大头**，
   但它跨项目共享，动它要先问用户。

## §5 本会话已结清的规则（**别再重问玩家**）

| 条目 | 结论 |
|---|---|
| 伤害类型 | **真实伤害 = 不可防御、但可"避免"**（卡牌/状态能挡，"防御技"不能）· 表见 `DICETHRONE_FLOW.md §4.3` |
| 骰面 | 女巫 **1/2/3=🌀扭曲 · 4=✳混沌 · 5=🩸法术 · 6=M王冠**（玩家贴英雄板图，已核）· 月精灵 **1/2/3=🏹 · 4/5=👣 · 6=🌙✳** |
| 骰型通用规则 | **骰型只用 4/3/2 颗时，剩余骰子任意**；只有用满 5 颗的（顺子/5 同型）才要求全中 |
| 双重麻烦 | **对子读法成立**（🌀🌀→爆裂 / 🌀🌀🌀→2 爆裂 / ✳✳→操控概率 / 🩸🩸→终极魔法 / MM→4 伤；另可弃 1 操控概率改 1 颗骰） |
| 厄运缠身 | 基础 6 伤 ＋ 掷 2 骰（🌀→+2 伤 / ✳→操控概率 / 🩸→扭曲现实 / M→+1 伤并**重掷该骰**）；骰型 **2🌀＋2✳（第 5 颗任意）** |
| 心灵震撼 | 奇数 → **替换** 5 为 8 真实伤害（**不是叠加**）；偶数 → 保持 5 并得操控概率 |
| 爆裂上限 | **3**（玩家给出） |
| 结束回合 | 只能玩家点（点不了那个横幅是定案）；`front_watch` 写 `TURN=Pn` 配哨兵叫醒 |

## §6 ⚠️ 本会话踩过的坑（**下一个人别再付同样的学费**）

1. **`roll.ps1` 的默认曾经会掷骰** ⇒ 只想看骰面必须加 `-NoRoll`。
   我把它当"读"连用 4 次，把玩家的实际投掷结果反复重掷，**玩家当场抓到**。⇒ **骰子判定以玩家报的为准。**
   2026-10-08 **已加护栏**：`-Roll` / `-NoRoll` 必须明说，**裸调用 `exit 2` 且不接触 TTS**（`play.ps1 roll` 同样不加 `-Roll` 只读）。
2. **批量字符串替换 = 灾难**：一次"路径去硬编码"的替换脚本连闯 5 祸（替换串被 PS 展开、引号被吃、BOM 叠成 3 个、
   dot-source 插到 `param()` 前、`param()` 默认值引用 config 变量），**连坏 22 个脚本**，手工抢救了两小时。
   ⇒ **动代码前先 `git commit`；要批量改就先 `Copy-Item` 备份；改完逐个用真解析器验证。**
3. **`param()` 必须是第一条语句**；**默认值里不能引用 config 变量**（那时还没求值）—— 默认 `''`，dot-source 之后回填。
4. **BOM 会自己繁殖**：`GetString(bytes)` 把 BOM 变成 U+FEFF 字符，`WriteAllText(..., UTF8Encoding(true))` 再加一个 ⇒ 每跑一次多一个 BOM，三个就解析失败。
   ⚠️ 2026-10-08 追加：**`check_ps1.ps1` 只扫 `tts\`（递归）—— `out\_selftest\` 里的临时脚本不在覆盖内**。
   我在那儿写了个**含中文**的分析脚本 ⇒ 没 BOM ⇒ PS 5.1 按 ANSI 读 ⇒ 字符串字面量损坏，脚本还"照常跑"，只是**静默给错答案**（阴性对照报 0、阳性对照也报 0）。
   ⇒ 临时脚本**要么全 ASCII，要么自己带 BOM**；出现"数字看着不对劲"时先怀疑编码，别先怀疑算法。
5. **旧路径会静默生效**：`DSH_HOME` 残留旧值时，脚本读写"看起来正常"但其实是空目录 ⇒ **启动先跑 `start-agent.ps1`**。
   同一个病 2026-10-08 又抓到两处：`validate_lua.js` 里写死的 luaparse 路径（项目搬出 `~/.dsh` 后那条路径**早就空了**，
   而它此前一直被当作"改了 Lua 就要跑"的校验器）；以及 `check_ps1.ps1` 那道写反的 BOM 回写条件（见 §6.8）。
   ⇒ 现在 `validate_lua.js` **相对仓库优先**，失败时**列出试过的每个路径**。
6. **`Infinite_Bag` 里取出的 token 没有图案** ⇒ 状态 token 的摆放**交给玩家**。
7. **沙箱只允许写工作区**：写项目目录（工作区之外）会报 `[sandbox: file access denied]` ⇒ 一次性提权重试，别硬绕。
8. **校验工具自己坏了整整一轮**（2026-10-08 才发现）：`check_ps1.ps1` 的回写条件写成 `if ($hadBom)`（应为 `if (-not $hadBom)`）
   ⇒ **它只回写本来就正常的文件，缺 BOM 的永远补不上，却照样打印 `BOM-FIXED`**。
   于是 3 个中文脚本"修"了几次仍报语法错，而我一直在怀疑脚本本身。⇒ **教训：校验器要有阳性对照**（故意造一个缺 BOM 的文件，看它是否真被改）。
9. **"能解析" ≠ "能用"**：事故还吃掉了 5 个脚本的 `param` 回填行 ⇒ 解析 0 错误，但 `Test-Path ''` / 空路径导出必挂。
   ⇒ **判据不是 `check_ps1.ps1` 通过，而是"每个 `''` 默认值都有回填"**；`diff_index.ps1` 的桩脚本自测是现成阳性对照（§4.5）。
10. **整篇重写会顺带把行尾改成 LF，把 diff 撑爆**：本仓库是 **CRLF**（无 `.gitattributes`，个别文件是 LF）。
    30 行的修复会显示成 200+ 行（`git diff --ignore-cr-at-eol` 可确认）⇒ 重写后按原样存回 CRLF + 单个 BOM。
11. **"只读"的基准脚本也会写游戏**（2026-10-08）：我写性能基线时把 `play.ps1 income` 当只读测了一次 ⇒ **悄悄给玩家 +1 CP**
    （已 `setCount` 复位并回读 ✅）。教训两层：① 任何"跑一遍看看"的脚本，先确认每个动词是读还是写 —— **`income` 是写动词**；
    ② **写动词一律要有显式开关**：现在 `income` 与 `attack`/`defense` 一致，默认只读、必须 `-Apply` 才写、`-WhatIf` 可预览。
12. **端口探测工具自己会撒谎**（2026-10-08）：`Get-NetTCPConnection -LocalPort 39999` 在本沙箱里**看不到明明在听的端口**
    （`netstat -ano` 和原始 `TcpClient.Connect` 都能看到）。我据此差点告诉用户"3080 空闲"，而 3080 上正跑着这个会话。
    ⇒ **判端口一律用 `netstat -ano | findstr :<port>` 或原始 TCP 连接**；别信 `Get-NetTCPConnection`。（与 §6.8/§6.9 同一课：**验证工具本身也要验**。）
13. **这个 harness 的工具壳是 Windows PowerShell 5.1**（`$PSVersionTable` = `5.1 Desktop`，不是 PS7）⇒ 我**直接**用 `Get-Content` /
    `Select-String` 读这些中文文件会按 **ANSI** 解码，**打印出来是乱码**（文件本身没坏，`read` 工具读同一个文件是好的）。
    修法：`Get-Content ... -Encoding UTF8`，或 `[System.IO.File]::ReadAllText/ReadAllLines`（默认 UTF-8）。
    ⚠️ **ASCII 模式的搜索不受影响**（`<用户名>`、`C:\Users\` 这类字节在 GBK 下一样）⇒ 之前的隐私扫描结论仍然有效；受影响的是**中文内容与中文模式**。
    （本条曾把真实用户名写进举例里，被 `tts\tests\test_agents_hygiene.ps1` 抓到 —— 这就是那个测试存在的理由。）

## §7 交接时的原始数据（万一文档与实物冲突）

- 关键 guid：我 HP `cdd19a` · 我 CP `675a1f` · 他 HP `ed238f` · 他 CP `5b2c43` · 我的骰 `f0738d/187cc1/656b32/e00b2e/910636` · 他的骰 `205873/26745c/aa8300/240f79/033d23`
- 我的手牌（**隐藏信息，已移出仓库**）：见 `tts\docs\archive\DICETHRONE_MYHAND.md`（该目录在 `.gitignore` 里，公开仓库看不到）
- 他挂起时的骰面：**1 / 4 / 4 / 3 / 4**
- git：`96dba9f`（当前：脚本全修完）· `4e5637a`（加本文件）· `49e35c9` · `781fe2c` · `3fbbde9`（基线）

## §8 上下文注入与隔离（DSH 的**实际**规则，2026-10-08 读源码确认）

> 源码：`@deepseek-ai/dsh-agent-instructions/lib/index.js`。**每次请求都注入**，所以这是本项目的"固定税"。

**注入什么**（按顺序）：
1. `$DSH_HOME\AGENTS.md` —— **用户全局**；文件名是**常量**，只要存在就第一个加进来
2. **项目链**：从**项目根**（`.git` 标记）**逐级到工作目录**，每级找 `AGENTS.md`/`CLAUDE.md`，再找 `AGENTS.local.md`/`CLAUDE.local.md`
3. 去重只有两种：**绝对路径**去重（同一份文件不会算两次）＋ **同目录内**去掉 trim 后内容相同的兄弟文件 ——
   源码原话：**跨目录即使内容完全相同也绝不合并**
4. 最后按**字节预算**渲染（超预算时先丢"更宽泛的"，即离项目根更远的）

**能用来"隔离"的旋钮**（`agent-instructions` 插件配置，默认值）：

| 旋钮 | 默认 | 用途 |
|---|---|---|
| `projectRootMarkers` | `['.git']` | 决定"项目根"在哪 ⇒ 决定链从哪开始 |
| `instructionFileCandidates` | `['AGENTS.md','CLAUDE.md']` | 只认一个名字就改这里（想彻底不读 `CLAUDE.md`） |
| `localInstructionFileCandidates` | `['AGENTS.local.md','CLAUDE.local.md']` | **机器专属 overlay**：不进仓库（**已 gitignore**）、**不参与去重**、叠加在最上面 |
| `maxBytes` | 由 harness 给 | 预算。⚠️ **别拿它当隔离手段** —— 它只会**截断**，会静默丢规则 |

⛔ **这个版本没有"忽略用户全局那份"的开关** —— `USER_GLOBAL_FILE = "AGENTS.md"` 是常量，存在就一定先加。
⇒ 要让全局那份不参与注入，**只有两条**：① `$DSH_HOME` 里没有 `AGENTS.md`；② **把 `DSH_HOME` 钉到本仓库根**（`start-agent.ps1` 就是这么做的）——
此时全局槽与项目槽指向**同一个绝对路径** ⇒ 按路径去重成**一份**（实测：2960 + 3925 = 6885 B/请求 → 2960 B）。
⚠️ 代价：`DSH_HOME` 同时是 harness 的家（sessions/凭据/profiles）⇒ **本机**要搬迁；**新机器**从一开始就这么配则没有代价。

**本项目的隔离姿势**：

| 内容 | 放哪 | 理由 |
|---|---|---|
| 项目专属纪律（骰子护栏/路径/param 规则） | 仓库的 `AGENTS.md` | 随 clone 走，人人相同（约 2.9 KB） |
| 机器专属（本机路径/端口/偏好） | `AGENTS.local.md` | overlay，**已 gitignore**，不会误提交进公开仓库 |
| 跨项目通用纪律 | `$DSH_HOME\AGENTS.md` | 各机器自己的事，仓库管不着 |

### 已落地（2026-10-08）—— 三个槽都真实存在了

| 槽位 | 文件 | 体积 | 谁管 |
|---|---|---|---|
| 项目 | 仓库 `AGENTS.md` | **2960 B** | git，随 clone |
| 机器 | 仓库 `AGENTS.local.md`（**gitignore**） | **1048 B** | 本机手写（换机器就不一样的事实） |
| 通用 | `$DSH_HOME\AGENTS.md` | **2924 B** | **源在仓库**：`tts\docs\HARNESS_HOME_AGENTS.template.md` —— 改模板 → 取其 `---` **之后的正文**覆盖过去（其余是文件头说明，不拷） |

- **每请求注入 = 2960 ＋ 1048 ＋ 2924 = 6932 B**。比最初"没隔离"的 6885 B 只多 **47 B（+1%）** —— 即"三个槽都在"几乎没多花钱。
- **2026-10-08 瘦身**：通用那份 4170 → **2924 B（−30%）**。砍的全是**解释性文字**：BOM 机制压成一句、8 条纪律各压成一行、
  删掉独立的「§5 边界」（并入文件头的 ⛔ 一行）—— **规则一条没删**。机制的完整说明（注入顺序 / 两种去重 / 预算 / 各类工作区注入什么）
  移进**模板头部**，那部分**不参与注入**。⇒ 通用那份的"知识"与"成本"从此可以分开维护。
- **有回归测试了**：`tts\tests\test_agents_hygiene.ps1`（**不需要 TTS，也不需要 Node**）：
  项目那份 ≤3 KB ＋ 必含 5 个承载性指针（`start-agent.ps1` / `DICETHRONE_STATE.md` / `PLAY.md` / `tts\config.ps1` / `check_ps1.ps1`）·
  **被 git 跟踪的文件里不许出现真实用户名或绝对用户路径** · `AGENTS.local.md` 必须被 gitignore 且 ≤2 KB ·
  **全局那份必须与模板正文逐字一致**（漂移检查）。它第一次跑就抓到我写进 §6.13 的真实用户名。
- ⚠️ 全局那份**在工作区之外** ⇒ 写它需要**一次提权**；而且**无法自动化**（"模板即源"是我们自己约定的，harness 不知道）。
- ⚠️ 测试会 `WARN`："全局那份比项目那份还大" —— 本项目**确实如此**（通用那份扛着 BOM/沙箱/PS 5.1/端口这些跨项目纪律），
  但它是**有用的信号**：哪天通用那份继续长胖，就该按 §1 的"边界"往下砍。

**想跨工具统一**（Cursor / Copilot / Claude Code / Codex 各读各的规则文件）⇒ 开源方案 **[rulesync](https://rulesync.dyoshikawa.com/)**（MIT）：
单一真源 → 按 target 生成各家文件、支持 project/global 两套作用域；它的支持表里**已列 DeepSeek Harness**。

### 试点结论（2026-10-08，**实测 rulesync 27.0.0**）—— 跑通了，但**建议暂不采纳**

做法：`out\rulesync_pilot\` 里放三份源 —— `00-generic.md` / `10-project.md`（都 `root: true`）＋ `90-machine.md`（`localRoot: true`），
`rulesync generate --targets agentsmd,claudecode --features rules` ⇒ 合成**单个** `AGENTS.md`（**5555 B / 77 行**），
顺序＝**文件名序**、段间空行分隔 ⇒ "通用 ＋ 项目"合并成一份这件事它做得对，`doctor` 与 `--dry-run` 也都能用。

- ⚠️ **收益来源要说清**：今天两份注入合计 **6885 B**（项目 2960 ＋ 全局 3925），试点产物 **5555 B（−19%）** ——
  但**省下来的不是 rulesync 的功劳，是我把"通用那半"写瘦了**（砍掉 §4 索引/加载机制与 §5）。
  ⇒ **不引入 rulesync 也能拿到这 19%**，只要把全局那份压瘦。
- 三条硬事实（都实测）：
  1. **rulesync 没有"DSH 用户全局"target**：global 模式只支持 Claude Code / Copilot / OpenCode
     ⇒ **`$DSH_HOME\AGENTS.md` 它生成不了**，得额外一步复制（那路径还在工作区之外 ⇒ 需提权）。
  2. **`localRoot: true` 必须配同 target 的 `root: true`**，否则直接报错：
     `localRoot: true requires a root: true rule to exist for target 'claudecode' (found in .rulesync\rules\90-machine.md)`
     ⇒ 想隔离出一份 `.local.md`，就得顺带生成那个工具的根文件。
  3. **它会往产物里塞自家样板**：`agentsmd` target 在开头插
     `# Additional Conventions Beyond the Built-in Functions` ＋ 一句英文说明（≈150 B，**每次请求都付**），并且**挪走了我们的 H1 位置**。
- **结论**：对本项目（Windows / PowerShell / 单一消费者只 DSH）⇒ **不引入**（Node 工具链 ＋ 目标样板 ＋ 复制步骤，换不到东西）。
  **但照抄它的"三份源"纪律**（就是本节上面那张表）；真要跨工具时（Cursor/Copilot/Codex）再上它。
  它最值钱的是 `generate --check`（CI 防漂移）—— 我们要的话，一条"AGENTS.md 体积上限 ＋ 必含小节"的检查就能替代。
