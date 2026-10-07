# HANDOFF.md —— 交接简报（2026-10-07 深夜收官）

> **谁读**：接手这个项目的下一个 agent（或几天后的我）。
> **怎么读**：本文件 = "现在到哪了 + 先干什么"；长期规矩在 `AGENTS.md`（本项目）与 `~/.dsh\AGENTS.md`（平台）；
> 每局开工照 `tts\docs\CURRENT.md` → `DICETHRONE_STATE.md` → `PLAY.md` 三步走。
> ⚠️ **先做 §1 的启动动作，否则所有脚本会读写一个不存在的旧目录。**

---

## §1 启动（必做，30 秒）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\<user>\projects\tts-agent\start-agent.ps1
#   → 把 $env:DSH_HOME 钉到项目根，然后起 dsh web
```
**为什么**：`DSH_HOME` 双重含义（harness home ＋ 本项目工作区根）。环境里若残留旧值 `C:\Users\<user>\.dsh`，
`tts\config.ps1` 会解析到**已被搬空的旧目录**，产物写丢、`live_index` 报 `ds.ps1 not found`。
**先验证**：`tts\play.ps1 status` 应回 `bridge=v12-callx` 且 `objs=136` 附近。

## §2 现在的状态

| | |
|---|---|
| 项目位置 | `C:\Users\<user>\projects\tts-agent`（独立 git 仓库，**46 文件跟踪**，最新提交 `96dba9f`） |
| 旧目录 `.dsh` | **项目产物不在这里**（sessions/storages/profiles/attachments ＋ 平台 `AGENTS.md`），但 **`archive\` 还在**：`~\.dsh\archive\tts-legacy\`＝33 个旧 `.ps1` · `~\.dsh\archive\system\` |
| 游戏 | **《王权骰铸》对局挂起中**（玩家说"先结束游戏"），随时可续 |
| 盘面 | **我（Blue/月精灵）27 HP / 4 CP** · **玩家（Red/猩红女巫）40 HP / 4 CP** · 物件 **136** · 桥接 `v12-callx` · 存档 `TS_Save_7.json` |
| 进度 | **R4 他的回合未收**（他重掷后骰面 1/4/4/3/4 = 🌀✳✳🌀✳ 命中「厄运缠身」但**尚未重新宣告**）→ 收完进 **R5（我的回合）** |
| 棋子状态 | 他 **爆裂 3/3（满）**；他该放 1 个「操控概率」token（要我提醒他放，`Infinite_Bag` 取出来的 token 没图案） |
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
4. 🟡 **开源准备**：`.gitignore` ✅ · 路径去硬编码 ✅（`tts\config.ps1` 是唯一解析层）· `README.md` ✅ · 4 个脚本修完 ✅ ·
   **还缺**：`LICENSE`（选 MIT/Apache-2.0）· 破坏性动词的 `-Apply` 护栏（`roll.ps1` 默认会掷骰，`play.ps1 -Apply` 直接写 HP）· 英文 README · 测试（socket 层可注入假回复）。
5. 🟡 **把 `diff_index.ps1` 的离线自测收进仓库**：现在脚手架只在 `out\_selftest\`（**`out\` 被 gitignore，会被清掉**）。
   值得提交成正式测试（注意 `check_ps1.ps1` 只扫 `tts\*.ps1`、**非递归** ⇒ 测试要么放平级、要么给它加 `-Recurse`）。重做只要三步：
   ① 从 `cache\live_index.csv` 造两份 fixture（移动/翻面/换容器/改 GMNotes/删除/新增各 1）；
   ② 写个只认 `-Out` 的**桩脚本冒充 `live_index.ps1`**；③ `diff_index.ps1 -Before b.csv -After a.csv -LiveIndex stub.ps1`
   ⇒ 期望 `SUMMARY added=1 removed=1 moved=1 flipped=1 reparented=1 state=1`（`exit 0`）。**这是唯一能在 TTS 不开时验证 diff 链的办法。**

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

1. **`roll.ps1 -Tray <seat>` 默认会先掷骰再读点数** ⇒ 只想看骰面必须加 **`-NoRoll`**。
   我把它当"读"连用 4 次，把玩家的实际投掷结果反复重掷，**玩家当场抓到**。⇒ **骰子判定以玩家报的为准。**
2. **批量字符串替换 = 灾难**：一次"路径去硬编码"的替换脚本连闯 5 祸（替换串被 PS 展开、引号被吃、BOM 叠成 3 个、
   dot-source 插到 `param()` 前、`param()` 默认值引用 config 变量），**连坏 22 个脚本**，手工抢救了两小时。
   ⇒ **动代码前先 `git commit`；要批量改就先 `Copy-Item` 备份；改完逐个用真解析器验证。**
3. **`param()` 必须是第一条语句**；**默认值里不能引用 config 变量**（那时还没求值）—— 默认 `''`，dot-source 之后回填。
4. **BOM 会自己繁殖**：`GetString(bytes)` 把 BOM 变成 U+FEFF 字符，`WriteAllText(..., UTF8Encoding(true))` 再加一个 ⇒ 每跑一次多一个 BOM，三个就解析失败。
5. **旧路径会静默生效**：`DSH_HOME` 残留旧值时，脚本读写"看起来正常"但其实是空目录 ⇒ **启动先跑 `start-agent.ps1`**。
6. **`Infinite_Bag` 里取出的 token 没有图案** ⇒ 状态 token 的摆放**交给玩家**。
7. **沙箱只允许写工作区**：写项目目录（工作区之外）会报 `[sandbox: file access denied]` ⇒ 一次性提权重试，别硬绕。
8. **校验工具自己坏了整整一轮**（2026-10-08 才发现）：`check_ps1.ps1` 的回写条件写成 `if ($hadBom)`（应为 `if (-not $hadBom)`）
   ⇒ **它只回写本来就正常的文件，缺 BOM 的永远补不上，却照样打印 `BOM-FIXED`**。
   于是 3 个中文脚本"修"了几次仍报语法错，而我一直在怀疑脚本本身。⇒ **教训：校验器要有阳性对照**（故意造一个缺 BOM 的文件，看它是否真被改）。
9. **"能解析" ≠ "能用"**：事故还吃掉了 5 个脚本的 `param` 回填行 ⇒ 解析 0 错误，但 `Test-Path ''` / 空路径导出必挂。
   ⇒ **判据不是 `check_ps1.ps1` 通过，而是"每个 `''` 默认值都有回填"**；`diff_index.ps1` 的桩脚本自测是现成阳性对照（§4.5）。
10. **整篇重写会顺带把行尾改成 LF，把 diff 撑爆**：本仓库是 **CRLF**（无 `.gitattributes`，个别文件是 LF）。
    30 行的修复会显示成 200+ 行（`git diff --ignore-cr-at-eol` 可确认）⇒ 重写后按原样存回 CRLF + 单个 BOM。

## §7 交接时的原始数据（万一文档与实物冲突）

- 关键 guid：我 HP `cdd19a` · 我 CP `675a1f` · 他 HP `ed238f` · 他 CP `5b2c43` · 我的骰 `f0738d/187cc1/656b32/e00b2e/910636` · 他的骰 `205873/26745c/aa8300/240f79/033d23`
- 我的手牌（我方隐藏信息，**不外传**）：`长弓 III`(3CP) · `月光魔法!`(1CP) · `月影袭人!`(2CP) · `隐匿射击 II`(1CP) · `噩梦`(2CP)
- 他挂起时的骰面：**1 / 4 / 4 / 3 / 4**
- git：`96dba9f`（当前：脚本全修完）· `4e5637a`（加本文件）· `49e35c9` · `781fe2c` · `3fbbde9`（基线）
