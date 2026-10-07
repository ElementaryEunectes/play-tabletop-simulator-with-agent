# tts\docs\ 文档索引 —— **要"还有哪些文件 / 什么在哪儿"时读这一页**

> 别翻目录、别整份读手册。每份文档顶部都有一句"什么时候读我"。
> ⚠️ **跨项目平台纪律**在 `~/.dsh\AGENTS.md`（自动注入）；**TTS 全套规则/工具/坑**在 **`TTS_RULES.md`**（做 TTS 工作时读一次）。
>
> 📏 **文档预算：13 份**。**新增门槛**（三条都要满足，否则并进已有文档）：
> ① 一句话说清"**什么时候读我**"；② 读场合**与现有文档不重叠**（**一个读场合 = 一份文档**）；③ 登记进下面这张表。
> ⭐ **开源的边界**：**本仓库只放"对任何 TTS mod 都成立"的通用工具链**；**某一款游戏专属的东西（状态/比分 · 规则与卡面 · 卡库 · 牌）不进仓库** ⇒ 一律放 **`local\games\<游戏>\`**。
> 判据一句话：**换个 mod 还成立 ⇒ 进仓库；只对这一局成立 ⇒ 留 `local\`。**
>
> ⇒ **超过 20 份必须先合并一份**。2026-10-08 先按"一个读场合一份"合并（19 → 14），再按**开源边界**把游戏专属内容搬进 `local\games\`（14 → 13）：
> `PLAY` ＋ `CURRENT` → **`DICETHRONE_STATE`** · `SCRIPTS` → **`TTS_RULES` §二** · `RULEBOOK` → **`DICETHRONE_FLOW` 附录 A** · `PITFALLS` ＋ `CONTEXT` → **`MAINTENANCE`**。

## 分层看**频率**（这是轴线）—— 同一层 = 同一次读 ⇒ 同一层只该有一份

⭐ **铁律（叠加在每一层之上，不可协商）**：**通用 ⇒ 进仓库；本局 ⇒ 进 `local\games\<游戏>\`。**
所以**同一层可能落成两份**：通用的在仓库里，本局的在 `local\`（下表逐行标注）。
判据：**换个 TTS mod 还成立 ⇒ 通用；只对这一局成立 ⇒ 本局。**

| 频率 | 读哪份 | 说明 | 变更 |
|---|---|---|---|
| **每回合** | **`PLAY.md`** | **通用**每回合卡：控制台动词 · 哨兵/叫醒 · 状态页维护纪律 —— 对任何 mod 都成立 | **每回合** |
| **每回合**（不进仓库） | `local\games\<游戏>\STATE.md` | **这一局的状态**（唯一真源：比分 · token · 待办 · guid）；当前是哪款见 `local\games\_current.md` | **每回合** |
| **开工前一次** | **`TTS_RULES.md`** | TTS 通用纪律（跟人配合 · 隐藏信息 · 以物为准）· **§二 工具清单**（`tts\*.ps1` 按频率分类）· 一回合循环 · 按钮定案 · TTS 特有的坑 · 换局 | 低 |
| **换局 / 冷启动** | `BOOTSTRAP.md` | 换存档 / 换模组 / 换游戏的**唯一**工作流（三种情形） | 低 |
| 按需（规则 · **不进仓库**） | `local\games\<游戏>\FLOW.md` | 该游戏的规则/技能/骰面 —— **顶部有"我要干什么 ⇒ 读哪节"路由表**；＋ **附录 A：官方规则书**（在哪 · 怎么拿 · 每页是什么） | 学到新规则时 |
| 按需（技术） | `TTS_WORKFLOW.md` | 跨游戏技术手册（索引 / 识别 / 几何 / 工具 / PowerShell 陷阱）· **顶部有路由表，按节取用** | 低 |
| 按需（维护） | **`MAINTENANCE.md`** | ① 踩过的坑 ×13（每条都付过真实代价）② 上下文注入与隔离（三槽 · 两种去重 · 字节预算 · 各类工作区注入什么） | 学到新坑时 |
| 按需（给人） | `USER_GUIDE.md` | **人怎么用**：开局 · 你只做两件事 · AI 何时请你帮忙 · 在哪说话 · 常见问题 | 低 |
| 按需（先例） | `PRIOR_ART.md` | 二手调研与先例（**冻结，别重搜**；含可搬/不可搬结论） | 冻结 |
| 不读 | `HARNESS_HOME_AGENTS.template.md` | `$DSH_HOME\AGENTS.md` 的**源**：`---` **以下是正文**（改完拷过去）；`tts\tests\test_agents_hygiene.ps1` 会核对两者逐字一致 | 低 |
| 永不 | `local\archive\`（**gitignore**） | 过期留档：旧简报 ×4 · 旧 STATE · 游城拓荒全部文档 · 旧 init 产物 —— **未随仓库分发** | 冻结 |

## 目录约定（保持干净 = 省 token）

- `tts\*.ps1` = **现役工具**；**清单与用途见 `TTS_RULES.md` §二**；死的 / 一次性的 / 实验性的一律进 `~\.dsh\archive\tts-legacy\`。
- `tts\tests\` = **离线自测（不需要 TTS、不需要存档）**：`test_diff_index.ps1`（桩冒充 `live_index.ps1` ＋ 合成 fixture）·
  `test_param_backfill.ps1`（每个 `''` 默认值必须被回填或判空）· `test_agents_hygiene.ps1`（三槽体积 / 承载性指针 / 隐私 / 漂移）。**改完脚本先跑它们。**
- `tts\lib\` = **从大脚本拆出来的实现模块**（当前只有 `play.*.ps1`：bridge/dice/rules/verbs），由主脚本 **dot-source**（同进程，无额外进程启动）⇒ 改哪块读哪块，别整份读主脚本。
- `tts\lua\` = TTS 模组的**全局 Lua**（`dsh_global.lua` = 桥接本体；`install_save2.ps1` 依赖它，**别动**）。`tts\validate_lua.js` = 改 Lua 前的校验器。
- `tts\tools\` = **跨语言小工具**：`fetch_pdf.js`（用 **Node 的 TLS 栈**下载 —— 沙箱里 `curl`/`Invoke-WebRequest` 会报 TLS 凭证错）·
  `pdf_images.js`（从**图片型** PDF 抽整页图）—— 规则书那条链用的就是这两个（见 `local\games\<游戏>\FLOW.md` 附录 A）。
- `tts\docs\` = 上面那张表里的文档。
- `cache\` = **产物**（可重建）：`front.txt` / `chan.txt`（哨兵心跳）· `dicethrone_cards.md`（游戏数据）·
  `live_index.csv` / `baseline.csv` / `obj_index.csv`（快照）· `hidden_zones.csv`（隐藏区规则）· 规则书 PDF 与整页图。
- **不进仓库的**（都在 `.gitignore`）：`AGENTS.local.md`（本机事实）· `local\`（私有：手牌 / 归档 / scratch）· `cache\` · `out\` · `logs\` · `shots\`。
