# HANDOFF.md —— 交接简报（2026-10-07 深夜收官）

> **谁读**：接手这个项目的下一个 agent（或几天后的我）。
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

## §8 上下文注入（摘要 —— 细节在 harness home 的 `platform\MAINTENANCE.md`）

- **每请求注入三份**：通用 `$DSH_HOME\AGENTS.md`（2924 B）＋ 项目 `AGENTS.md`（**3656 B**，含开源边界铁律）＋ 机器 `AGENTS.local.md`（1048 B）＝ **7628 B**。
- 想只注入一份 ⇒ 用 `start-agent.ps1` 起（`DSH_HOME` 钉到仓库根，两个槽同路径去重）。⛔ harness **没有"忽略全局那份"的开关**。
- 注入顺序 / 两种去重 / 字节预算 / **各类工作区会注入什么** / rulesync 试点结论 ⇒ 全在 harness home 的 `platform\MAINTENANCE.md`；
  回归测试 ⇒ `tts\tests\test_agents_hygiene.ps1`；"模板即源"的复制关系 ⇒ harness home 的 `platform\HARNESS_HOME_AGENTS.template.md`（**已迁出仓库**）。
