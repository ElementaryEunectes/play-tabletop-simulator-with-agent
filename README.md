# TTS 代玩工作区（DSH × Tabletop Simulator）

在 **Tabletop Simulator** 里由 AI 代打桌游的工作区：玩家（人类）只做**决策**和点「**结束回合**」，
其余全部棋子操作由 agent 通过 TTS 的消息桥接完成。

⭐ **本仓库 = 与具体游戏无关的通用工具链**（桥接 · 脚本 · 工作流 · 纪律）—— 这才是开源的内容。
⛔ 某一款游戏专属的东西（状态/规则/卡面/卡库/牌）**不进仓库**；**当前在打哪一款是本机信息** ⇒ 见 `local\games\_current.md`。

> ⚠️ **本仓库含"跑起来要用的东西"，不含隐私与生成物** —— 凭据/会话/日志/缓存/归档都在 `.gitignore` 里。
> 🌐 English: [`README.en.md`](README.en.md)

## 怎么启动（**普通人：双击 `start.cmd`**）

在资源管理器里双击本仓库根目录的 **`start.cmd`** 就行 —— ⛔ **别直接双击 `.ps1`**（那会用记事本打开）。
它会把工作目录切到本仓库、钉好 `$DSH_HOME`，再启动 DSH；没装 `dsh` 时它会停下并告诉你怎么装。

**第一次用，按这个顺序**：Windows → **Node.js** → `npm i -g @deepseek-ai/dsh` → **Tabletop Simulator**（Steam，付费）＋ 订阅目标模组 →
**把桥接烤进存档**（`tts\docs\BOOTSTRAP.md`）→ 双击 `start.cmd` → 在 TTS 里载入那个存档。
⚠️ 本仓库**不含任何游戏规则/卡面文本**（那是某一款游戏的内容，放 `local\games\`，不进仓库）。

## 怎么读（**别整份读，按角色取**）

| 要干什么 | 读什么 |
|---|---|
| 平台纪律（跨项目，自动注入） | `AGENTS.md` |
| **做 TTS 工作**（工具地图 · 按钮 · 桥接坑 · 一句话约定） | `tts\docs\TTS_RULES.md` |
| 每局开工 | `tts\docs\PLAY.md`（**通用**每回合卡）＋ `local\games\<游戏>\STATE.md`（该局状态，**不进仓库**）· 换 mod 才需 `tts\docs\BOOTSTRAP.md` |
| 本局规则/技能/骰面 | `local\games\<游戏>\FLOW.md`（**不进仓库**）·
    卡面文本 `cache\dicethrone_cards.md`（`cache\` 不入库，脚本会重建/手抄） |
| 脚本清单（⭐常用 / 💤休眠 / 改名前必读的引用图） | `tts\docs\TTS_RULES.md（§二 工具清单）` |
| 换局 / 冷启动 | `tts\docs\BOOTSTRAP.md` |
| **人怎么用（拿给玩家看）** | `tts\docs\USER_GUIDE.md` |
| 文档与目录总索引 | `tts\docs\README.md` |
| **改完怎么验证** | `tts\check_ps1.ps1`（递归补 BOM ＋ 真解析器）→ `tts\tests\test_*.ps1`（**不需要 TTS**） |

## 跑起来需要什么

1. **Windows + PowerShell 5.1**（脚本用了 `System.Drawing`、WinRT、GDI 抓屏）。
2. **DSH**（提供哨兵与工具调用；本工作区就是 `$DSH_HOME`）。
3. **Tabletop Simulator** + 目标模组；`tts\lua\dsh_global.lua` 通过 `install_save2.ps1` 灌进存档建立桥接。

## 在新机器上（**新 clone 的第一步**）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tts\doctor.ps1      # 只读体检 + 注入成本预测
powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1   # 全部脚本：补 BOM + 真解析器
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_diff_index.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_param_backfill.ps1
```

`doctor.ps1` 会顺便算出**每请求注入多少字节**：本仓库的 `AGENTS.md`（约 2.9 KB）＋ **你这台机器 harness home 里的 `AGENTS.md`**。
第二份**不在本仓库里** —— 它是 harness 的**用户全局**文件（`$DSH_HOME\AGENTS.md`）。若 `DSH_HOME` 就指向本仓库，两份会**去重成一份**（`start-agent.ps1` 就是这个用法）。

⚠️ 本仓库用 `.gitattributes`（`* -text`）**锁住行尾与编码**：clone 出来的字节与提交的完全一致。**别改成 `text=auto`** —— 那会一次性重写所有文件的 blob，还可能碰坏 `.ps1` 必须保留的 UTF-8 BOM。

## 路径配置（**不要再把用户名写进脚本**）

所有机器相关的路径由 **`tts\config.ps1`** 解析一次，其余脚本只引用它的变量：

```powershell
$env:DSH_HOME      = 'D:\somewhere\.dsh'   # 工作区根（默认：脚本所在 tts\ 的上级）
$env:TTS_SAVES_DIR = 'D:\...\Saves'        # TTS 存档目录（默认：我的文档\My Games\Tabletop Simulator\Saves）
$env:TTS_IMAGES_DIR= 'D:\...\Mods\Images'  # TTS 图片缓存（默认：同上）
```

⚠️ **`param()` 必须是脚本的第一条语句**，配置的 dot-source 要放在它**之后**；
且**不要在 `param()` 默认值里引用 config 的变量**（那时还没求值）——正确写法是默认 `''`，dot-source 之后再回填。

## 改代码的规矩（**本仓库付过代价**）

1. **先提交再改**：`git add -A && git commit -m "before: xxx"`。改坏了 `git checkout -- <file>` 一键回滚。
2. **改完任何 `.ps1` 立刻**：`powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1`
   （它会补 BOM 并用真解析器全量校验）。
3. ⛔ **不要用"批量字符串替换"改活代码**（本项目就是这么连坏 22 个脚本的：替换串被 PowerShell 展开、
   引号被吃掉、BOM 被叠成 3 个）。要批量改就先 `cp -r` 一个备份目录，改完逐个验证。
4. 含中文的 `.ps1` **必须 UTF-8 带 BOM**；新写的一次性脚本尽量只写 ASCII 注释。
5. **解析通过 ≠ 能用**：本仓库栽过一整类 bug —— `param()` 默认 `''` 却没在 dot-source 之后回填，
   脚本能启动、然后往空路径写。`tts\tests\test_param_backfill.ps1` 专治这一类。
6. **校验器要有阳性对照**：`check_ps1.ps1` 和 `test_param_backfill.ps1` 都曾"报成功但其实没看见问题"
   （一个 BOM 回写条件写反、一个正则锚在行首匹配不到任何东西）⇒ 拿一个**故意造坏的探针**喂它，看它真能报错再信它。

## 护栏（会改桌面的动词）

- **`roll.ps1` 必须明说意图**：`-Roll` 才掷、`-NoRoll` 只读；**裸调用 `exit 2` 且不接触 TTS**。
  骰子扔了收不回来，而且那是对手的骰子。`play.ps1 roll` 同样"不加 `-Roll` 只读"。
- **`play.ps1 -Apply` 是唯一的 HP/CP 写入**：加 `-WhatIf` 会打印 `WILL WRITE  HP moon 26 -> 22  (-4)` 而**一个字节都不写**；
  真写之后脚本自己回读，不一致立刻 `BAD DATA` 停。
- `install_save2.ps1`（唯一允许写存档的脚本）有 `-DryRun`。其余全部只读。

## 已知状态

- ✅ **31 个 `.ps1` 全部通过真解析器**（`check_ps1.ps1`，**递归**，含 `tts\tests\`）：0 解析错误、BOM 齐。
- ✅ **离线自测**（不需要 TTS）：`tts\tests\test_diff_index.ps1`（桩脚本冒充 `live_index.ps1` ＋ 合成 fixture ⇒ 六类变化全中）·
  `tts\tests\test_param_backfill.ps1`（每个 `''` 默认值都必须被回填或判空）。
- ✅ **无个人路径**：树里已无 `C:\Users\<名字>` 之类硬编码（`tts\config.ps1` 是唯一解析层）。
- ⏸ 对局处于**挂起**态：**现状与续局步骤不在仓库里**（`local\games\_current.md` 指到具体文件）。
- ⚡ **每回合成本**（2026-10-08 实测）：回合开局用**一条** `tts\play.ps1 turn` ≈ **1.5s**，替代原来 `status`+`roll`+`tabread` 三条的 ~2.9s；
  `say.ps1` 每条消息 **0.79s**（原 ~1.7s，少了两次子进程）。**每个 PowerShell 进程启动固定 ~0.35s ⇒ 合并命令就是省时间**，TTS 往返不是瓶颈。
- 🧾 `LICENSE` = **MIT**（见下）。

## 相关项目（prior art —— 我们站在谁旁边）

完整调研（每项的关键事实 · 可搬/不可搬结论）在 **[`tts\docs\PRIOR_ART.md`](tts/docs/PRIOR_ART.md)**。摘要：

- **[Smirk1921/tts-toolkit](https://github.com/Smirk1921/tts-toolkit)**（MIT）—— TTS 图包作者工具链：**hub 守护（39997）独占唯一连接再扇出**给 CLI / VSCode / **MCP agent**、存档 pack/unpack（字节级一致）、**游戏内 Lua 测试**、工坊发布。
  **我们没接它**（现有重试已够稳，且接入是协议改动），但它解决的是与我们同一类"抢 39998"问题。配套 [tts-lua-hub](https://github.com/Smirk1921/tts-lua-hub)（上游插件 2023-04 起停更后的 fork）。
- **[libin7099901/TabletopSimulatorCompanion](https://github.com/libin7099901/TabletopSimulatorCompanion)** —— 目前唯一完整的「LLM × TTS」项目，但**只做规则问答**，不操作棋子；我们的"**从存档取 PDF URL**"技巧来自它。
- **[rolandostar/tts-editor](https://github.com/rolandostar/tts-editor)**（Node）· **[LucasOe/tts-external-api](https://github.com/LucasOe/tts-external-api)**（Rust）—— External Editor API 的两个独立参考实现；我们走的是**同一个协议**。
- **[cloudwu/cardocr](https://github.com/cloudwu/cardocr)** —— 卡面 OCR/VLM 路线（我们的对照面：我们读 `FaceURL` 的 40 位 hash，**免费且确定**）。
- **[pr1m8/haive-games](https://pr1m8.github.io/haive-games/overview.html)** —— LLM 桌游 agent 框架；**明确不装**（它绑定自己的环境，接进来会得到与桌面不一致的镜像状态）。
- 学术：arXiv [2510.25595](https://arxiv.org/abs/2510.25595)（信息不对称下的通信与校验 —— 我们只搬了**训练无关的 verifier 那半**）· [Tabletop Games Framework](https://rdgain.github.io/assets/pdf/TAG.pdf) · BALROG。

**我们的位置**：公开项目里**仍然没有**"AI 当玩家在 TTS 里打完整一局"的实现（2026-10-08 复核过一遍）。
现有开源要么是**工具链/连接层**（tts-toolkit），要么是**规则问答**（Companion），要么是**别的平台**（play-with-agents）。
本项目补的是**玩家层**：状态语义化读取 · 隐藏信息纪律 · 每回合 token/时间预算 · 人机分工（人只决策 ＋ 点「结束回合」）。

## 许可与第三方

本仓库的**代码与文档**按 **MIT** 授权（见 `LICENSE`，Copyright (c) 2026 ElementaryEunectes）。
它**不覆盖**：**Tabletop Simulator**（Berserk Games）· **《王权骰铸》/ Dice Throne** 及其卡面文本与美术（Roxley / MINDVG）·
创意工坊模组本身。**规则/卡面文本不随仓库分发**（自用便签在 `local\games\`）：那份便签转抄了部分卡面文字，**不含任何卡图** ——
图片与卡面文本库都在 `cache\`，不进仓库。
`tts\validate_lua.js` 依赖 **`luaparse`**（MIT），但**未随仓库分发**：`npm i luaparse`，或设 `LUAPARSE_DIR`。
