# TTS 代玩工作区（DSH × Tabletop Simulator）

[![gates](https://github.com/ElementaryEunectes/tts-agent/actions/workflows/gates.yml/badge.svg)](https://github.com/ElementaryEunectes/tts-agent/actions/workflows/gates.yml)

> 🤖 **本仓库的代码与文档主要由 AI（DSH agent）撰写** —— 人负责**决策、审阅与拍板**，每个提交记着"为什么改"。
> 这不是免责声明，而是本项目要验证的东西：**agent 能不能留下可交接、可门禁、可复现的活**。
> 落档纪律 ⇒ `CONTRIBUTING.md` §5.4（**新文件在头注释里写明由谁撰写**）。

在 **Tabletop Simulator** 里由 AI 代打桌游的工作区：玩家（人类）只做**决策**和点「**结束回合**」，
其余全部棋子操作由 agent 通过 TTS 的消息桥接完成。

⭐ **本仓库 = 与具体游戏无关的通用工具链**（桥接 · 脚本 · 工作流 · 纪律）—— 这才是开源的内容。
⛔ 某一款游戏专属的东西（状态/规则/卡面/卡库/牌）**不进仓库**；**当前在打哪一款是本机信息** ⇒ 见 `local\games\_current.md`。

> ⚠️ **本仓库含"跑起来要用的东西"，不含隐私与生成物** —— 凭据/会话/日志/缓存/归档都在 `.gitignore` 里。
> 🌐 English: [`README.en.md`](README.en.md)

## 怎么启动（**普通人：双击 `start.cmd`**）

在资源管理器里双击本仓库根目录的 **`start.cmd`** 就行 —— ⛔ **别直接双击 `.ps1`**（那会用记事本打开）。
它只做一件必要的事：**把工作目录切到本仓库**（否则项目链不注入本仓库的 `AGENTS.md`）；**默认不动 `$DSH_HOME`、不设任何环境变量** ⇒ harness home 那份 `AGENTS.md`（若存在）**照旧会被注入**（启动时会打印它到底注入没注入）。想把**本项目的**全局槽清零 ⇒ 填 `start-agent.ps1` 里的 `$ProjectDshProfile`（或传 `-DshProfile <名字>`；机制 ⇒ `tts\docs\INJECTION.md` §4 方案 A′）。没装 `dsh` 时它会停下并告诉你怎么装。

📖 **指令文件（`AGENTS.md` 等）怎么被注入、每个请求要花多少字节、安装时该怎么放** ⇒ `tts\docs\INJECTION.md`（装机器前读一次；`tts\doctor.ps1` 可复核）。

**第一次用，按这个顺序**：Windows → **Node.js** → `npm i -g @deepseek-ai/dsh` → **Tabletop Simulator**（Steam，付费）＋ 订阅目标模组 →
**建这一局的骨架**（`tts\setup.ps1 -InitGame <slug>`，从 `tts\templates\` 生成 `local\games\<slug>\`）→
**把桥接烤进存档**（`tts\docs\BOOTSTRAP.md`）→ 双击 `start.cmd` → 在 TTS 里载入那个存档。
📋 **不确定从哪下手就先跑 `tts\setup.ps1`**（默认**只读**）：它打印"到第一回合"的 8 步并转给 `tts\doctor.ps1` 体检。
⚠️ 本仓库**不含任何游戏规则/卡面文本**（那是某一款游戏的内容，放 `local\games\`，不进仓库）。

### 首次上手要花多久、花什么（**先知道这个再决定**）

**钱**：Tabletop Simulator（Steam，付费，常打折）· 目标模组（创意工坊，多为免费）· **没有别的服务** —— 桥接、哨兵、脚本全在**本机**跑，除 DSH 自己的模型调用外不产生费用。

| 步骤 | 预计 | 备注 |
|---|---|---|
| 装 Node.js ＋ `npm i -g @deepseek-ai/dsh` | ~5 min | 一次性 |
| 装 TTS ＋ 订阅目标模组 | ~15 min | 主要是下载时间 |
| **把桥接烤进存档**（`BOOTSTRAP.md` §2）＋ 让玩家重载 | ~10 min | 一遍就会；之后换局也走这条 |
| **首次"教一款 mod"**：认物（`objects.json` ＋ 地图）· 卡库（可选）· **回合校准** | **~30–60 min** | ⭐ **这是大头**，也是"通用工具链"真正要做的活 |
| 之后每局开工 | **~5 min** | 重烤 ＋ 重载 ＋ 重挂哨兵（见 `PLAY.md`） |
| **合计到"打完第一回合"** | **≈1–1.5 h** | 判据就是它：陌生人 1 小时能否打完一回合 |

⚠️ **诚实的四条前置**（别买完才发现）：
1. **需要 DSH**（这个 agent harness）—— 它提供哨兵与工具调用；没有它，这套脚本只是一堆脚本，回合交接会退化成手动轮询。
2. **游戏专属动词需要一个"控制层"**（`local\games\<游戏>\control\play.ps1`，按 `BOOTSTRAP.md` §2 写）。**没有它时 `play.ps1 status` 仍可用**（桥接版本 · 物件数 · 在位玩家 · 轮到谁），但 `play.ps1 <游戏动词>` 会明确报 `NO PART` 并指向那节。
3. **换 mod 要重做"回合校准"**（座位坐标每款都不同）：`tts\tools\turn_calib.ps1 -Discover` ＋ `-Answer`，约 5 分钟。
4. **离线门禁 7 条里有 1 条要额外依赖**：`bridge primitives (Lua)` 需要一个 JavaScript 版 Lua VM（`fengari`，本机放在 `local\scratch\luatest`）。**没装它时那条显示 `NOT RUN`（不算失败）**，其余 6 条照跑；要跑全 7 条 ⇒ `npm i fengari` 装到那个目录，或用环境变量 `FENGARI_DIR` 指过去。


## 怎么读（**别整份读，按角色取**）

| 要干什么 | 读什么 |
|---|---|
| 平台纪律（跨项目，自动注入） | `AGENTS.md` |
| **做 TTS 工作**（按钮定案 · 能力边界 · 认牌 · TTS 行为坑 · 一句话约定） | `tts\docs\TTS_RULES.md` |
| 每局开工 | `tts\docs\PLAY.md`（**通用**每回合卡）＋ `local\games\<游戏>\STATE.md`（该局状态，**不进仓库**）· 换 mod 才需 `tts\docs\BOOTSTRAP.md` |
| 本局规则/技能/骰面 | `local\games\<游戏>\FLOW.md`（**不进仓库**）·
    卡面文本 `cache\<游戏>_cards.md`（`cache\` 不入库，脚本会重建/手抄） |
| 脚本清单（⭐常用 / 💤休眠 / 改名前必读的引用图）· 改游戏内 Lua · 写入前检查 | `tts\docs\MAINTENANCE.md` §5–§7 |
| 换局 / 冷启动 | `tts\docs\BOOTSTRAP.md` |
| **人怎么用（拿给玩家看）** | `tts\docs\USER_GUIDE.md` |
| 文档与目录总索引 | `tts\docs\README.md` |
| **改完怎么验证** | `tts\check_ps1.ps1`（递归补 BOM ＋ 真解析器）→ `tts\tests\test_*.ps1`（**不需要 TTS**） |

## 跑起来需要什么

1. **Windows + PowerShell 5.1**（脚本用了 `System.Drawing`、WinRT、GDI 抓屏）。
2. **DSH**（提供哨兵与工具调用）—— harness home 与工作区是**两个概念**：默认分开（`$DSH_HOME` 指向 harness 的家）；加 `-RepoAsHome` 才把本仓库当 `$DSH_HOME`。
3. **Tabletop Simulator** + 目标模组；`tts\lua\dsh_global.lua` 通过 `install_save2.ps1` 灌进存档建立桥接。

## 在新机器上（**新 clone 的第一步**）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tts\doctor.ps1      # 只读体检 + 注入成本预测
powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1   # 全部脚本：补 BOM + 真解析器
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_diff_index.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_param_backfill.ps1
```

`doctor.ps1` 会顺便算出**每请求注入多少字节**：本仓库的 `AGENTS.md`（**≈1.9 KB**）＋ **你这台机器 harness home 里的 `AGENTS.md`**。
第二份**不在本仓库里** —— 它是 harness 的**用户全局**文件（`$DSH_HOME\AGENTS.md`）。若 `DSH_HOME` 就指向本仓库（只有加 `-RepoAsHome` 才这么设），两份会**去重成一份**。

⚠️ 本仓库用 `.gitattributes`（`* -text`）**锁住行尾与编码**：clone 出来的字节与提交的完全一致。**别改成 `text=auto`** —— 那会一次性重写所有文件的 blob，还可能碰坏 `.ps1` 必须保留的 UTF-8 BOM。

⭐ **这七条门禁在 CI 上也跑**（`.github\workflows\gates.yml`，**Windows** runner —— 门禁是 PowerShell ＋ Windows 路径）：CI 会替你装上第 6 条需要的 `fengari`，所以那边是 **7/7**；万一装不上，那条会如实报 **`NOT RUN`（不算失败）**而不是假装绿。这就是"新 clone 第一步"应该看到的结果。

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

1. **先提交再改**（`git checkout -- <file>` 一键回滚）· ⛔ **不要用"批量字符串替换"改活代码**（本项目就是这么连坏 22 个脚本的）· 含中文的 `.ps1` **必须 UTF-8 带 BOM**。
2. **改完任何 `.ps1` 跑 `tts\check_ps1.ps1`**（补 BOM ＋ 真解析器全量校验）；**解析通过 ≠ 能用** —— `param()` 默认 `''` 却没在 dot-source 后回填那一类 bug，由 `tts\tests\run_all.ps1` 里的 `param backfill` 专治。
3. **改测试判定逻辑前先造一个"坏"的阳性对照**（本仓库的校验器两次"报成功但其实没看见问题"）。完整规矩 ⇒ **[`CONTRIBUTING.md`](CONTRIBUTING.md)**；本机沙箱/编码 ⇒ `tts\docs\MAINTENANCE.md` §0。

## 护栏（会改桌面的动词）

- **`roll.ps1` 必须明说意图**：`-Roll` 才掷、`-NoRoll` 只读；**裸调用 `exit 2` 且不接触 TTS**。
  骰子扔了收不回来，而且那是对手的骰子。`play.ps1 roll` 同样"不加 `-Roll` 只读"。
- **`play.ps1 -Apply` 是唯一的 HP/CP 写入**：加 `-WhatIf` 会打印 `WILL WRITE  HP moon 26 -> 22  (-4)` 而**一个字节都不写**；
  真写之后脚本自己回读，不一致立刻 `BAD DATA` 停。
- `install_save2.ps1`（唯一允许写存档的脚本）有 `-DryRun`。其余全部只读。

## 已知状态

- ✅ **`tts\` 下 45 个 `.ps1` 全部通过真解析器**（`check_ps1.ps1`，递归；口径 = 含 `tests\` / `tools\` / `lib\`）：0 解析错误、BOM 齐。
- ✅ **离线门禁 7 条**（不需要 TTS）：唯一入口 `tts\tests\run_all.ps1`（清单 ⇒ `CONTRIBUTING.md` §3）。
- ✅ **无个人路径**：树里已无 `C:\Users\<名字>` 之类硬编码（`tts\config.ps1` 是唯一解析层）· `LICENSE` = **MIT**。
- ⏸ 对局处于**挂起**态：**现状与续局步骤不在仓库里**（`local\games\_current.md` 指到具体文件）。
- ⚡ **每回合成本**（2026-10-08 实测）：回合开局一条 `tts\play.ps1 turn` ≈ **1.5s**（替代 `status`+`roll`+`tabread` 的 ~2.9s）；`say.ps1` 每条 **0.79s**。**每个 PowerShell 进程固定 ~0.27 s（271 ms；权威基线 ⇒ `tts\docs\MAINTENANCE.md` §1b）⇒ 合并命令就是省时间**，TTS 往返不是瓶颈。

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
> ⚠️ **上面这一处是全仓库唯一的"点名"**（法律声明必须让权利人可识别）。其余任何地方**都不准出现真游戏名**：
> 一律用 `<游戏>` / "对局型 mod" 这类占位或描述 —— 门禁 `tts\tests\test_agents_hygiene.ps1` 会逐字检查（`README.en.md` 的对应段同理）。
`tts\validate_lua.js` 依赖 **`luaparse`**（MIT），但**未随仓库分发**：`npm i luaparse`，或设 `LUAPARSE_DIR`。
