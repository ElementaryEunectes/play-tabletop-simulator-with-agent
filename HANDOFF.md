# HANDOFF.md —— 交接简报（2026-10-07 深夜收官）

> **谁读**：接手这个项目的下一个 agent（或几天后的我）。
> 🆕 **2026-10-09 会话纪要见 §9 —— 最新状态与待办以 §9 为准。**
> **怎么读**：本文件 = "现在到哪了 + 先干什么"；长期规矩在 `AGENTS.md`（本项目）与 `~/.dsh\AGENTS.md`（平台）；
> 每局开工：`local\games\_current.md` → 该游戏 `STATE.md`（状态 · 待办）＋ `tts\docs\PLAY.md`（通用动作）——**先做 §1 的启动动作**。
> ⚠️ **先做 §1 的启动动作，否则所有脚本会读写一个不存在的旧目录。**
> 🛠️ **维护参考**：本仓库要点在 `tts\docs\MAINTENANCE.md`；**坑 ×15 ＋ 上下文注入与隔离**已迁到 harness home 的 `platform\MAINTENANCE.md`（动手改脚本 / 排查怪现象前读）。

---

## §1 启动（必做，30 秒）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <本仓库>\start-agent.ps1
#   → 把 $env:DSH_HOME 钉到项目根，然后起 dsh web
```
**为什么**：`DSH_HOME` 双重含义（harness home ＋ 本项目工作区根）。环境里若残留旧值 `<用户目录>\.dsh`，
`tts\config.ps1` 会解析到**已被搬空的旧目录**，产物写丢、`live_index` 报 `ds.ps1 not found`。
**先验证**：`tts\play.ps1 status` 应回 `bridge=v12-callx` 且 `objs=136` 附近。

## §2 现在的状态 ⇒ **不在仓库里**

对局现状 · 续局步骤 · 已结清的规则 · 原始 guid 全部在 **`local\games\<游戏>\`**（`_current.md` 指到具体文件；`local\` 在 `.gitignore` 里）。

**为什么**：本仓库只放**对任何 TTS mod 都成立**的通用工具链。

## §4 待办（按优先级）

1. ✅ **脚本已全部修完**（2026-10-08，提交 `96dba9f`）。原来只当"4 个语法坏脚本"，实际有**两层**：
   | 层 | 脚本 | 真相 |
   |---|---|---|
   | 语法 | `tts\diff_index.ps1` · `tts\card_index.ps1` | **只是丢了 BOM**（中文被当 ANSI 读 ⇒ 一堆假语法错）。**根因在 `check_ps1.ps1` 本身**，见 §6.8 |
   | 语法 | `tts\index_images.ps1` · `tts\tts_api.ps1` | 真被改写坏（`$`→`i`、`)` 被删、`'`→`C`、`J` 被吃；`@()`→`@(`；一处硬编码输出路径）。**逐行手工重写** |
   | 运行 | `tts\obj_index.ps1` · `tts\bags_dump.ps1` · `tts\install_save2.ps1` · `tts\bootstrap.ps1` · `tts\diff_index.ps1` | 少了"dot-source 之后回填默认路径"那行 ⇒ **解析 0 错误、一跑就写空路径**。已按 `TTS_RULES.md（§二 工具清单）`/文档补回原文件名 |
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
   ✅ `LICENSE`（MIT）**已入库**，署名 `Copyright (c) 2026 ElementaryEunectes`（仓库 git 身份是 `DSH agent / agent@local`，不适合当版权行）。
   ✅ **publish 前的隐藏信息检查已完成（2026-10-08）**：跟踪文件里**只剩指针**（本文件 §2 与 `local\games\_current.md` 指向 `local\games\<游戏>\`，那里在 `.gitignore` 里）⇒ 公开仓库看不到牌面。
   📌 **铁律**：牌、计划、任何隐藏信息**只写进 `local\games\<游戏>\MYHAND.md`**（`local\` 整个不进仓库）。
5. ✅ **`diff_index.ps1` 的离线自测已收进仓库**：`tts\tests\test_diff_index.ps1`（＋ `fake_live_index.ps1` 桩 ＋ `fixtures\*.csv`）
   与 `tts\tests\test_param_backfill.ps1`；`check_ps1.ps1` 已改**递归**，测试自身也受 BOM ＋ 真解析器校验。
   ⚠️ 改这两个测试**必须重跑阳性对照**（故意造一个坏探针看它是否真报错，见 §6.8/§6.9）。
6. ✅ **效率优化（2026-10-08）**：回合开局压成**一条命令** `play.ps1 turn`（实测 **1.5s**，替代 `status`+`roll`+`tabread` 的 ~2.9s）；
   `say.ps1` 改成**单进程就地 TCP**（**0.79s** vs ~1.7s）；`income` 补上写护栏（默认只读，见 §6.11）；
   项目 `AGENTS.md` **6432 → ~2100 字节**（这份**每次请求都在计费**，所以易变的「已知状态」全部推给 STATE/HANDOFF）；
   随身卡 **4219 → ~2100**（现在按铁律拆成两半：通用的 `tts\docs\PLAY.md` ＋ 本局的 `local\games\<游戏>\STATE.md`）；新增 **`tts\docs\USER_GUIDE.md`**（人怎么用）。
   ⇒ **下一次开局的默认动作：`tts\play.ps1 turn`，别再 status+roll 各跑一次。**
   **为什么没动 Lua**：实测往返不是瓶颈 —— 一个 PowerShell 进程启动固定 **0.35s**，而一次 TTS 往返只 ~40ms
   （`play.ps1 turn` 17 次往返仍是 1.48s）。把 17 次并成 1 次大约省 0.6s，却要**重装存档 + 请玩家重载**（改 `dsh_global.lua` 的代价）
   ⇒ **不划算，别去做**，除非以后有一次性几十条 act 的新场景。
   **为什么 `AGENTS.md` 只砍到 2856**：剩下的是**不变量**（纪律/路径/启动）。易变的东西全在 STATE/HANDOFF —— 它们是**按需读**，
   而 AGENTS.md **每个请求都注入**。再往下砍就得把纪律搬进按需文档，代价是"新会话可能不读"。**平台那份 `~/.dsh\AGENTS.md`（3925 字节）现在是注入的大头**，
   但它跨项目共享，动它要先问用户。
   （**2026-10-08 后续**：通用那份已按 §8 落地并**瘦身到 2924 B**，三份合计 **6932 B/请求** —— 数字见 §8。）
7. ✅ **官方规则书落地（2026-10-08）**：规则书**就在存档里** —— `guid 0f4dfd` 的 `Custom_PDF`，nick「规则书（中2.3英2.4版本）」。
   - `obj_index.ps1` 现在会记 **`CustomPDF.PDFUrl`**（新增 `src` / `pdfurl` 两列）⇒ 一眼取到 URL。
   - 已完成整条链：**取 URL → Node 下载（9.1 MB / 15 页）→ 抽整页图 → 缩略索引**；三步命令、**逐页目录**、以及"为什么必须用 Node 下载"
     全部写在 **`local\games\<游戏>\FLOW.md` 附录 A**（⛔ 不进仓库）；**技术本身通用**（见 `PRIOR_ART.md` §7.4 与本条）—— 换任何 mod 同理。
   - ⇒ **规则有争议先查它**：p05 状态效果图标表 · p08 防御/结算文本 · p09 伤害类型表 · p11 回合详解 · p15 速查表。
   - ⚠️ 它是**基础规则 ＋ 枪手示例页**，**不含**月精灵/猩红女巫的卡面数值 ⇒ 英雄专属数值仍以**桌上卡面**为准（`crop_zoom.ps1` 裁图读）。
8. 🚧 **让第三方"简单部署 · 廉价游玩"**（2026-10-08 自评：**目前还不行** —— 机制层已开源可用，卡在下面五块，按性价比排序）：
   - **A（~30 min）修"开箱即坏"的引用**：`AGENTS.md`（注入）让 agent 读 `local\games\<游戏>\STATE.md` 与 `local\games\_current.md`，
     但**全新 clone 里这两份都不存在**，而仓库**没有骨架模板**（唯一的 template 是给 harness home 的）
     ⇒ 加 `tts\docs\<游戏>_STATE.template.md` ＋ `FLOW.template.md`（各 ~20 行），并在 `AGENTS.md` 补一句"**没有就先照 `BOOTSTRAP.md` 建**"。
   - **B（~1 h）README 顶部写清期望**：首次上手三步 · **时间/成本期望** · **已知限制**
     （Windows only · 每个 mod 要人肉教一次 · **每回合仍需人类点「结束回合」** · **不含游戏规则**）。
   - **C（2–4 h）`setup.ps1` 安装向导**：查 Node / DSH / 凭据 / TTS / 端口 / 存档 → 引导烤桥接 → 自动跑 `doctor.ps1`。
   - **D（半天–一天，决定性的一块）把"认物"从写死变成可配置 ＋ 半自动**：`bootstrap.ps1` 现在**按上一局《游城拓荒》写死**
     （`TTS_RULES.md` §二 有 ⚠️）；目标是 `local\games\<游戏>\objects.json`（座位 / HP / 资源 / 牌堆 / 隐藏区映射）
     ＋ 用 `obj_index.ps1 -Hist` 名字直方图 ＋ `crop_zoom.ps1` 裁图辅助的标注流程 ⇒ **做完这条，"任何 mod"才真成立**。
   - **E（半天）做出"能看见"的成品**：一个最小公开 mod 的 demo ＋ 30 秒录屏 ⇒ 让陌生人在 30 秒内判断它行不行。
   - 📌 两条现实（别在 README 里含糊）：**"廉价"成立** —— 注入 ~7.6 KB/请求，钱花在**模型步数**与**人工**上，不在注入；
     **"快速"只在"已教好的 mod"上成立**，第一次上手是**小时级**。
   - 📌 判据（做完 A–E 再看一遍）：陌生人只有**公开仓库 + Windows + TTS + 一个 workshop mod**，能不能在**一小时内**打完一回合？

## §6 ⚠️ 踩过的坑 ⇒ 已拆到 harness home 的 `platform\MAINTENANCE.md`

- **动手改 `.ps1` / 改流程 / 排查怪现象之前，先读那一份**（13 条，每条都付过真实代价）。
- 本文件只留"现在到哪了 + 先干什么"；坑的细节不在这里重复（否则每次会话都在读参考材料）。

## §7.9 待办：回合令牌要重装存档（**v13-turntoken**）

桥接 Lua 已加 `turn_token` / `turn_state`（自制可点回合令牌：点一下把回合号写进昵称 ⇒ `diff_index.ps1` 现在也差 `nick`）。
⛔ **尚未生效**：`dsh_global.lua` 是**烤进存档**的 ⇒ 需要一次 `install_save2.ps1` 重装 ＋ **请玩家重载**，然后 `{cmd="turn_token"}` 自举、`{cmd="turn_state"}` 读回验证。

**实机验收清单**（TTS 开着、存档重载之后逐条打勾）：

1. `{cmd="ping"}` ⇒ `v` = `v13-turntoken`（确认桥接是**新版**，否则说明存档没重装成功）。
2. `{cmd="turn_token"}` ⇒ `ok=true` · `created=true` · 记下 `guid`；**再跑一次**应 `created=false`（幂等）。
3. 让玩家**点一下那个令牌** ⇒ `{cmd="turn_state"}` 的 `turn` 从 `0` 变 `1`、`nick` = `DSH-TURN 1`。
   （我不需要"点"：`{cmd="call", guid=<令牌>, fn="dshBump"}` 能直接调同一个函数 —— 但那是我自己的簿记，**mod 的回合机另说**。）
4. `tts\diff_index.ps1 -Snapshot` → 点一次 → 再跑 `diff_index.ps1` ⇒ 应出现 **`NICK (昵称变化)`** 段（`was`/`now`）且 SUMMARY 含 `nick=1`。
5. **对照实验（它相对 `front_watch.ps1` 的价值）**：把 TTS 切到**后台**再点一次 ⇒ 令牌状态**照样读得到**（`front.txt` 此时读不出 `TURN`）。
6. 任一条不符 ⇒ 记下 `{cmd="turn_state"}` 的**原始返回**与 TTS 的 `Console`（Lua 报错打在那里），**别猜**。

## §8 上下文注入（摘要 —— 细节在 harness home 的 `platform\MAINTENANCE.md`）

- **每请求注入三份**：通用 `$DSH_HOME\AGENTS.md`（2924 B）＋ 项目 `AGENTS.md`（**3656 B**，含开源边界铁律）＋ 机器 `AGENTS.local.md`（1048 B）＝ **7628 B**。
- 想只注入一份 ⇒ 用 `start-agent.ps1` 起（`DSH_HOME` 钉到仓库根，两个槽同路径去重）。⛔ harness **没有"忽略全局那份"的开关**。
- 注入顺序 / 两种去重 / 字节预算 / **各类工作区会注入什么** / rulesync 试点结论 ⇒ 全在 harness home 的 `platform\MAINTENANCE.md`；
  回归测试 ⇒ `tts\tests\test_agents_hygiene.ps1`；"模板即源"的复制关系 ⇒ harness home 的 `platform\HARNESS_HOME_AGENTS.template.md`（**已迁出仓库**）。
---

## §9 2026-10-09 会话纪要（**接手先读这一段**；本节状态优先于上文）

### 9.1 今天落地了什么

- **按项目屏蔽全局纪律的开关找到了**（发布时用）：`dsh tts-agent web`。机制 = profile 的 `cordis.patch.yml` 把指令插件（id `agent-instructions`）的 `dshHome` 指向**空目录** ⇒ 只有该 profile 零注入；会话/凭据不用搬、不用 junction。目录已建好：`~\.dsh\profiles\tts-agent\`。
- **但本项目暂时不屏蔽**：平台宪章已**恢复注入**（`~\.dsh\AGENTS.md` 3,752 B），默认 profile = `web`。
- **平台层已迁出仓库** ⇒ `<harness home>\platform\`：宪章模板 · `MAINTENANCE.md`（坑 ×17）· `dsh_profile.ps1`（**已废**）· 快照 `local\archive\platform_2026-10-09\`。
- **新增 `tts\docs\INJECTION.md`**：安装者视角讲三槽 / 三条硬规则 / 成本 / 安装时怎么放 / **§4 变体：保留全局纪律 ＋ 按项目屏蔽**。
- **去重**：`AGENTS.local.md` 只留本机事实（2,210 → 1,826 B）；项目 `AGENTS.md` 与宪章去重（3,621 → **3,518 B**，命令留一行、解释收一处）＋ 修正三行**已过期**的描述（"全局槽是空的"等）。
- **门禁总入口 `tts\tests\run_all.ps1`**（新）：裸调用 · 子进程**自己写结果文件**（**无 cmd、无管道**）· 启动前**置空 `$LASTEXITCODE`**（防陈旧值冒充成功）· 三个测试改为文件重定向抓子进程。
- **`diff_index.ps1`**：`nick` 纳入差分（回合信号）；明确"**实机只报 4/6 类**"（`reparented`/`state` 需 `parent/gm/ss`，而 live 索引把它们置空）＋ 无值时打印警告。
- **回合令牌（桥接 `v13-turntoken`）**：`{cmd="turn_token"}` 自举 · `{cmd="turn_state"}` 读回；点一下 ⇒ 回合号写进**昵称** ＋ 存 `script_state` ＋ 翻转。
- **`PRIOR_ART.md` §8**：生态如何解"AGENTS.md 污染"（五类做法 ＋ 可搬/不可搬，含 Cursor/OpenCode/rulesync/harness-scope）。
- **清理**：删掉 `local\scratch` 下 **15,094** 个死依赖文件（工作区 18,489 → **3,395**）。

### 9.1b 2026-10-09 第二场（接手会话：D0 → D，两件都做完了）

- **D0 完成**（`e22911d`）—— `tts\diff_index.ps1` · `live_index.ps1` · `fake_live_index.ps1` **不再有 `exit`**，失败路径 `return 1`；`tests\test_diff_index.ps1` 改成**同进程调用**（`& ... 6>&1`），**不再 spawn 内层 PowerShell** ⇒ **六个门禁在受限模式下全绿**（实测），「需要完全权限」那条权宜作废（`CONTRIBUTING.md` §3 已改）。新增两个用例：case 7 钉"错误路径把码**当值**返回给调用方"（旧的 `exit 1` 在这里读到的是 0），case 8 用**解析器 token** 静态禁止这条链里的脚本出现 `exit`。
- **D 完成**（`2f7e5cd`）—— "本款数据进代码"清干净：
  - `card.ps1` 的两处：别名表 → `cache\<game>_alias.json`（**缺文件不是错误**：退化为纯文本匹配，提示只在**查不到时**打印一行）；"最接近的候选"里写死的四个牌名 → 按同一个字重合度现算。
    ⚠️ **本局功能没丢**：老表是 **dicethrone 自己**的（不是游城拓荒的）⇒ 已按原样写到 **`cache\dicethrone_alias.json`**（`hex→厄运缠身` · `bow→长弓` · `moon→月精灵/月光/月之/月影` · `witch/scarlet/scar→猩红女巫` · `cp` · `draw` · `block` 全保留），**实测** `-Q hex` / `-Q bow` / `-Q 厄运缠身` / `-Q zzzz`（NOT FOUND）四条都对。**换新游戏要自己建这一份**。
  - `bootstrap.ps1`：整份重写成**通用渲染器**，认物规则全部来自 `local\games\<游戏>\objects.json`（schema 写进 `BOOTSTRAP.md` **§1b**：seats ＋ `seatRow`/`seatGrid`/`rows`/`deckByHash`/`nearRef` 五种区块）。**缺文件 ⇒ 报错并指出它要的路径**，不再打空表冒充答案。新增 **`-Inventory`**＝ name/nick/图 hash 三个直方图（**不需要** objects.json，因为它就是用来写出第一份的）；在真索引上实测：1659 行 → 19 names / 1077 nicks / 245 hashes → `cache\obj_inventory.md`。
  - `config.ps1` 新增 `$DshGameAlias` / `$DshGameObjects`（**路径只有这一处定义**）。
  - 新增第 6 个门禁 `tts\tests\test_game_data.ps1`：拿**假游戏** fixture 跑两个工具，**决定性的两条是否定用例**（没有别名文件时英文词必须查不到；换成"只有座位"的最小 objects.json 时专属区块必须消失）—— 这是"数据不在代码里"唯一能被证明的方式。阳性对照：往 `card.ps1` 里塞回一条硬编码别名 ⇒ 门禁红 2 条（随后按字节还原，SHA256 核对）。
  - ⚠️ **代价与教训**：`bootstrap.ps1` 的重写踩了三个 PowerShell 坑（`$L`/`$l` 是同一个变量 · `return @(一个)` 会退化成标量而标量 PSCustomObject 的 `.Count` 是 `$null` · 双引号里 `` ` `` 会吃掉 markdown 反引号）＋ 一个参数名坑（`-Db` 撞 `-Debug` 的**参数别名**，而 `Get-Alias db` **看不见**它）。细节都写进代码注释了。
- **本项目没有 `local\games\dicethrone\objects.json`** ⇒ 现在 `bootstrap.ps1` 对它**报错是设计如此**（旧版是对它打一份空表）。要恢复"盘点"能力：照 `cache\obj_inventory.md` 写一份，或先跑 `-Inventory` 再看。
- **`exit` 语义被实测纠正**（见 §9.6）—— 平台上那句"`&` 调别人的脚本、它会 `exit` ⇒ 终止你的整个会话"**不成立**（至少 PS 5.1 不是这样）；真正会杀掉调用者的是**没有脚本边界**的 `exit`（`iex` / 手贴代码）。

**今天的提交（最新在下）**

```textcd1a234 test(gates): the gate runner stops using cmd, stops trusting a stale exit code, and writes where a confined child can actually write
b6889e5 docs(charter): the injected charter described a world where no global slot existed - three lines were stale
6d206de docs(charter): dedupe the project AGENTS.md against the global charter - imperatives stay, explanations move to one place
0d20fcd docs: keep the global charter injected for now, dedupe the local overlay, and write down the release-time switch
a64f336 docs: how to run the gates when the agent sandbox confines child processes
3635d40 test(gates): make the offline gates survive a confinement that silently drops piped stdout
05b55fa research(prior-art): section 8 - how other agent projects scope and de-contaminate their instruction files
d2971a8 test(gates): one entry point that cannot report a green for a test that never ran
6cf2ac6 feat(turn): a clickable Lua turn token, and nickname becomes a diffed signal
dea6abe fix(diff): live mode reports 4 of 6 change classes - say it out loud, and pin it with a contract test
afffcbc docs(bootstrap): step 0 points at INJECTION.md, and stops describing the retired injection layout
b214339 docs: a user-facing explanation of the instruction-injection mechanism, for installers
1092635 docs: per-request injection 6799 -> 4873 bytes, without losing a single rule
815a190 feat(launch): method A - no global instruction slot at all; the launcher stops building the junction profile by default
59f52ee docs: mark the platform essentials OPENSOURCE-TEMP and move them from the machine overlay into the tracked maintenance card
840a838 refactor: move the platform layer out of the toolkit (to the harness home); the repo keeps the TTS toolkit and its gates
168dac1 charter: slim the cross-project AGENTS.md (4476 -> 3742 B); move never-read-while-working bytes to the template header
ae78e06 charter: add a code-consistency section to the cross-project AGENTS.md (template + installed copy)
11e35b2 feat(profile): give each project its own harness home, so the user-global AGENTS.md injects nothing
3347c7b feat(launcher): start.cmd - double-clickable, and the docs now say so first
c5d622f docs: correct three statements that config.ps1 made obsolete, and the launcher's own header
71ad408 docs: make TTS_RULES section 4 the single source of truth for the End Turn verdict
6e643c1 test(gates): run_all.ps1 was committed without its BOM, so every gate run dirtied the tree
e22911d fix(diff): the diff chain can be called in-process - no exit statements, and its gate stops spawning PowerShell
2f7e5cd feat(data): game recognition data moves out of the code - card aliases and table objects become files
```

### 9.2 本机环境的三条限制（**都付过代价**；细节见平台层坑 16 / 17）

1. **火绒 HIPS** —— 规则「隐藏执行PowerShell」会拦"沙箱以隐藏方式起 powershell" ⇒ 症状：整条命令**无输出、退出码 -1**。修法：信任区加 `node.exe` · `%APPDATA%\npm\node_modules\@deepseek-ai\dsh\` · `powershell/pwsh/cmd/git` · `~\.dsh\` · `%TEMP%\dsh-*` · 工作区；或把该规则改成"询问/允许"。
   ✅ **2026-10-09 已用火绒自己的日志查证**（规则名 / 触发者 / 单次 vs 叠加 / 查法）⇒ `tts\docs\MAINTENANCE.md` §0 ＋ 本文件 §9.7。
2. **`0xC0000142`（DLL 初始化失败）** —— `Start-Process`（含 `-WindowStyle Hidden`）与**经 `cmd` 启动**都会死（后端成文限制，README L127）⇒ **都别用**；本项目脚本已改成裸调用。
3. **管道会静默丢输出 ＋ 不可见 PowerShell 被拦（后者是*安全属性*，不是 bug）**
   - `& x 2>&1` 在受限模式下是"子进程跑了、退出码 0、文本为空" ⇒ 抓输出**一律写文件再读** ✓
   - **内层再起 `powershell.exe`（不可见执行）会被沙箱/杀软拦** —— 沙箱的职责就是约束"命令**及其后代**"（后端 README L12）；而"隐藏执行 PowerShell"本身是恶意软件的典型手法 ⇒ **拦得对**。原来 `tts\tests\test_diff_index.ps1` 会去 spawn `diff_index.ps1`，**这个 spawn 本来多余**。
   - ✅ **正解（顺从而不是绕过）**：把 `tts\diff_index.ps1` 改成**用 `return` 而不是顶层 `exit`**（`ds.ps1` 早就这么做 ✓）⇒ 测试**同进程调用**它 ⇒ 门禁在受限模式下也能全绿。「完全权限」只是权宜，不是修法。
   - ✅ **2026-10-09 已做完**（`e22911d`）：`diff_index` / `live_index` / `fake_live_index` 全部去掉 `exit`，`test_diff_index.ps1` 同进程调用 ⇒ **六个门禁实测在 `workspace-write` 下全绿**；契约由 token 级静态检查钉死。⚠️ 但**理由要按 §9.6 的实测改写**：`exit` 并不会杀掉 `&` 调用者，"去掉 `exit`"换来的是**返回码当值**＋不再依赖"内层 spawn"这条被沙箱拦掉的路。

⇒ **工位建议**：**不必再切「完全权限」**（2026-10-09 起六个门禁在受限模式下可跑）。受限模式下的规矩只剩两条：**抓子进程输出写文件再读**；**别用 `Start-Process`**。注意**门禁脚本本身也不再 spawn 子 PowerShell**（`run_all.ps1` 仍会起一层——它需要读退出码与输出标志；那一层实测可用）。

### 9.3 待办（**下一步从这里挑**）

- ✅ **D0**（2026-10-09 完成，`e22911d`）—— 顺沙箱的安全属性修门禁：diff 链去掉顶层 `exit` ⇒ 测试同进程调用 ⇒ **六个门禁在受限模式下全绿**，不再需要"完全权限"这个权宜。
- ✅ **D**（2026-10-09 完成，`2f7e5cd`）—— 清掉"本款数据进代码"：别名表 → `cache\<game>_alias.json`；`bootstrap.ps1` 认物 → `local\games\<游戏>\objects.json`（＋ `-Inventory` 半自动产出）；**验证**＝假 `GAME=fake` fixture 的第 6 个门禁（含两条否定用例）。
- 🔴 **D2（D 的尾巴，建议接着做）—— 给当前这局写 `local\games\dicethrone\objects.json`**：现在 `bootstrap.ps1` 对 dicethrone **报错**（设计如此）。原料已经生成好：`cache\obj_inventory.md`（1659 行索引 ⇒ 19 names / 1077 nicks / 245 hashes）。填完就能重新"一条命令盘点"。⚠️ 这是**本局数据**，写进 `local\`（不进仓库）；schema 见 `BOOTSTRAP.md` §1b。（别名表那一份**已经做完**：`cache\dicethrone_alias.json`。）
- **A** —— `STATE` / `FLOW` 模板（新游戏起手；`BOOTSTRAP.md` §6 有清单但无模板）。
- **C** —— `setup.ps1` 向导（检测 ＋ 写 `local\games\_current.md` ＋ 生成模板 ＋ 打印下一步）。
- **E** —— demo / 录屏（需要 TTS）。
- **回合令牌验收**（`v13-turntoken`）—— **仍未做**：需 `install_save2.ps1` 重装存档 ＋ **玩家重载** ⇒ 按 **§7.9 的 6 条清单**逐条验（第 1 条：`{cmd="ping"}` 应回 `v13-turntoken`）。本次会话**没碰它**（要玩家在场；且它需要 TTS 在跑）。⚠️ 重装前先 `tts\play.ps1 status` 看桥接版本，别把重装与"存档没重载"混为一谈。
- **火绒放行** —— 否则工具调用会**间歇**被整条掐掉（本场没遇到；真遇到先看 §9.2 第 1 条）。

### 9.4 开源可用性体检（结论）

- ✅ **能**：环境体检（`tts\doctor.ps1`）· 启动（`start.cmd`）· 桥接烤进存档（`install_save2.ps1`）· 通用工具链（`bootstrap.ps1` / `live_index.ps1` 对游戏名的命中数 = **0**）· 缺 `_current.md` 时**报错清晰**。
- ❌ **还不能**：**换一款 mod 直接开打** ⇒ 卡在 **A**（没模板）与 **D**（`card.ps1` 写死本款牌名，铁律违规的现成反例）。
- ⚠️ **平台层十几条坑不随仓库走**（开源用户只有 `tts\docs\MAINTENANCE.md` §0）⇒ 新机器搭建成功率受影响。
- ⚠️ **"等玩家点结束回合"依赖 DSH 的 sentinel** ⇒ 换 agent 平台会退化成轮询。

### 9.5 关键数字

- **每请求注入 ≈ 9.5 KB**：平台宪章 3,950（本轮 +198：`exit` 那条改准确）＋ 项目 `AGENTS.md` 3,518 ＋ 本机 overlay 2,299（上一场 1,826 → 2,299）；发布时切 `dsh tts-agent web` ⇒ ≈ **5.7 KB**。
- 工作区文件 **3,395**；跟踪 `.md` 14 份；`tts\` 下 **40** 个 `.ps1`（＋ fixtures 里 5 份测试数据）。
- 平台层：宪章模板 6.9 KB · `MAINTENANCE.md` ≈ 24 KB（坑 ×17）· 快照 `local\archive\platform_2026-10-09\`。
- 门禁：`powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\run_all.ps1`（要证据时加 `-OutFile <路径>`）⇒ 现在 **6 条**（新增 `game data (files)`）。

### 9.6 本次实测纠正：`exit` 到底会不会杀掉调用者（**平台宪章那句话不准确**）

平台宪章说："`&` 调别人的脚本前，确认它不 `exit` —— `exit` 会终止**调用者的整个会话**。"（项目 `AGENTS.md` 同款）
本场为了 D0 做了**四种调用形态**的实测（PowerShell 5.1，脚本文件 `b.ps1` 里 `exit 3`）：

| 调用形态 | 结果 |
|---|---|
| `$o = & 'b.ps1' 6>&1`（**捕获**） | 调用者**继续跑**，`$LASTEXITCODE = 3` |
| `& 'b.ps1'`（裸调用） | 调用者**继续跑**，码同上 |
| `. 'b.ps1'`（点源，含**顶层**点源） | 调用者**继续跑**，码同上 |
| `iex (Get-Content -Raw 'b.ps1')`（**无脚本边界**） | ⛔ **进程当场以 3 结束**，后面的语句一条都不执行 |

⇒ **准确的说法**：`exit` 在**脚本文件**里会被**那个文件自己的边界**接住（点源也是），所以 `&`/`.` 调用者不会死；**真正危险的是"没有脚本边界"的 `exit`** —— `iex`、手贴进控制台的代码、或直接跑 `-File` 的那个文件自己（后者是**期望**行为）。
⇒ 因此"D0 去掉 `exit`"的**收益**应该这样说：**返回码变成调用方拿得到的一个"值"**（`return 1`），不再依赖 `$LASTEXITCODE` 这个全局副作用；**不是**"修掉了一个会杀掉调用者的 bug"。
⚠️ **顺带纠正一条旧记录**：`CONTRIBUTING.md` / `AGENTS.local.md` 原先写"`test_diff_index.ps1` 只能在**完全权限**下跑"。本场在 `workspace-write` 下**先跑了一次基线**，那时门禁**就已经 5/5 全绿**（内层 spawn 也起来了）⇒ 那条限制在本机**当前状态下已不复现**（火绒放行或别的原因，未查明）。所以 D0 的收益**不是**"救活一个跑不了的门禁"，而是：**删掉一个不必要、且被文档记为会被拦的进程形态** ＋ 返回码当值 ＋ 契约可被 token 检查钉死。
✅ **已改准确（2026-10-09 第二场，用户要求）**：
1. 平台宪章 `$DSH_HOME\AGENTS.md` 那条已按实测重写，并**同步三份逐字一致**：真源 `platform\HARNESS_HOME_AGENTS.template.md` ＋ 禁用副本 `platform\AGENTS.md.disabled`（`test_agents_hygiene` 的漂移检查仍绿）。新措辞：`exit` 在**脚本文件**里被该文件自己的边界接住（`&`/`.` 调用者不死，码只进 `$LASTEXITCODE`）；只有**没有脚本边界**的 `exit`（`iex`、手贴代码）才**当场结束进程**；**stdout 即结果**的终端工具可保留 `exit`。宪章 **3,752 ⇒ 3,950 B**（每请求 +198 B）。
2. ⚠️ **上一版 §9.6 里"本仓库 `AGENTS.md` 同款那句"是错的**：grep 证实那条**只在平台宪章里**，项目 `AGENTS.md` 没有它 ⇒ 项目文件未动。
（另：`tts\docs\MAINTENANCE.md` 随本轮更新 —— 门禁清单补上 `run_all` ＋ `test_game_data`、删掉"`test_diff_index` 需完全权限"，并新增 **§0 火绒 HIPS 实测证据与查法**；结论见 §9.7。）

### 9.7 火绒到底拦了什么 —— 实测查证（2026-10-09 第二场，用户要求）

**证据来源**：火绒自己的日志 `C:\ProgramData\Huorong\Sysdiag\log.db`（SQLite，表 `HrLogV3_60`，HIPS 事件 `fname='sysprot'`）
＋ `applog.db`（`AppRunInfoList_60` = 程序运行记录）。**查法（可复核的 SQL / 判据）写在 `tts\docs\MAINTENANCE.md` §0**，此处不重复。

**结论 1 —— 命中的是 harness 自己的形状，不是某条命令"格外可疑"**：
规则 `rp_name_execcreate_powershell_hidden`（"隐藏执行 PowerShell"），`p_procname` **永远是 `node.exe`**
（`dsh web` / `dsh-subprocess-local` / `dsh-sandbox-windows-acl`），被创建的是
`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "<本次工具调用的脚本文本>"`
⇒ **每一次工具调用都是这个形状**，agent 无法让它变成"非隐藏"，所以**规范操作不能使规则不再匹配**。

**结论 2 —— 但只有个别调用真被处置**：全天 `sysprot` 共 **5 条**：4 条在 **18:53–18:59（上一场）**、
1 条在 **20:13:58（本场）**。本场那条正是我把三种"隐藏执行"惯用法**塞进同一条命令**的探针
（`cmd /c powershell` ＋ 嵌套 `powershell` ＋ `Start-Process -WindowStyle Hidden`）⇒ 那一次调用**整条被掐**
（无输出、退出码 `-1`，与 §9.2 记的症状同形）。对照实验：三种惯用法**各自单独**用、以及一条 **7.3 KB 的长内联命令**，
**全部跑通且日志无新事件** ⇒ **不是"长"、也不是"单独用"触发，叠加/成串才触发**（`clsname: risk_prot_v6`＝行为评分）。

**答"是不是你操作不规范"**：**一半是**。
- **是**：本场唯一被处置的那条，是**我自己**把 malware 味最重的三种写法堆在一条命令里；而它们本来就不必要
  （`cmd /c` 与"测试里再生一个 powershell"本轮已从门禁中删除；`Start-Process` 是明令禁止的）⇒ **规范操作能少踩**。
- **不全是**：上一场那 4 条命中的脚本正文只是普通的"改文件"辅助函数，没有那三种惯用法 ⇒ 只要 harness 仍以隐藏方式起 PowerShell，
  规则就会**继续匹配**；"规范"只能减少**额外叠加**，不能消除命中。⇒ 命令被掐时**不要**一律归因于杀软，也**不要**以为"规范了就一劳永逸"。

**未能确定的（诚实清单）**：`action:0` 的枚举含义读不出来（规则库 `db\hips.db` 是加密的 `VARDYHFS` 头）⇒
无法判定那 4 条究竟是"允许"还是"拦下"；也没有配置变更审计线索可证明用户那次"放行"就是本场不再触发的原因。
