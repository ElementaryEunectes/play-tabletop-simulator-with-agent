# AGENTS.md —— **TTS 代玩项目宪章**（`C:\Users\<user>\projects\tts-agent`）

> 这是**项目**级宪章：只讲"在这个项目里怎么干活"。
> 跨项目纪律在 `~/.dsh\AGENTS.md`（自动注入，别在这里重复）。
> ⛔ 具体某局游戏的规则/比分**不放这里** —— 放 `tts\docs\<游戏>_*.md`。
> 📌 **刚接手 → 先读 `HANDOFF.md`**（§1 启动动作 · §2 现状 · §4 待办 · §6 已踩过的坑）。

## 这个项目是什么

在 **Tabletop Simulator** 里由 AI 代打桌游：**玩家（人类）= 只做决策 + 点「结束回合」**；其余棋子操作全部由 agent 通过
TTS 消息桥接完成。当前在打**《王权骰铸》（Dice Throne）**，与 **P1（玩家，Red/猩红女巫）** 对局，我 = **P2（Blue/月精灵）**。

## 怎么启动（**先做这一步，否则脚本会读错目录**）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\<user>\projects\tts-agent\start-agent.ps1
# 它会把 $env:DSH_HOME 钉到项目根，再启动 dsh web
```
**为什么必须**：`$env:DSH_HOME` 有双重含义 —— ① harness 自己的 home ② 本项目的 `tts\config.ps1` 解析出的工作区根
（`cache\ out\ logs\ shots\` 都在那）。若环境里还留着**旧值**（例如 `C:\Users\<user>\.dsh`），脚本会静默读写一个**不存在**的目录。

## 一局的固定读法（**别整份读手册**）

| 顺序 | 读什么 | 作用 |
|---|---|---|
| 1 | `tts\docs\CURRENT.md` | 现在在玩哪款 + 指向哪份 STATE/FLOW（1 行） |
| 2 | `tts\docs\DICETHRONE_STATE.md` | ⭐ **唯一真源**：HP/CP · 状态 token · 手牌 · **待办** |
| 3 | `tts\docs\PLAY.md` | **每局随身卡**：本局控制台动词 + 每回合步骤 + 哨兵/STATE 约定 |
| 4 | 按需查小节 | `tts\docs\DICETHRONE_FLOW.md`（规则/技能/骰面/伤害类型） · `cache\dicethrone_cards.md`（卡面文本） |

**TTS 通用规则**（工具地图 · 「结束回合」按钮 · 桥接坑 · 隐藏信息纪律 · 换局流程）在 **`tts\docs\TTS_RULES.md`** —— 开工读一次。
**脚本清单**（哪个能改、哪个休眠、跨脚本引用图）在 **`tts\SCRIPTS.md`**。

## 目录怎么分

```
tts-agent\                      ← 项目根 = 工作区根（$DSH_HOME）
├── AGENTS.md                   本文件（项目宪章）
├── README.md                   对外说明（含路径配置与改码规矩）
├── start-agent.ps1             启动器：钉好 DSH_HOME 再起 dsh
├── tts\
│   ├── config.ps1              ⭐ 唯一的路径解析层（其余脚本只引用它的变量）
│   ├── *.ps1                   现役工具（清单见 tts\SCRIPTS.md）
│   ├── lua\dsh_global.lua      TTS 模组的桥接脚本（install_save2.ps1 依赖，别动）
│   └── docs\                   全部文档（索引 docs\README.md；归档 docs\archive\）
└── cache\ logs\ shots\ out\    运行时产物（不进 git；由脚本重建）
```

## ⛔ 项目专属纪律

1. **改任何 `.ps1` 之前先 `git commit`**（本仓库已初始化；`git checkout -- <file>` 就是后悔药）。
2. **`param()` 必须是脚本第一条语句**：`config.ps1` 的 dot-source 要放在**它之后**；
   **不要在 `param()` 默认值里引用 config 变量**（那时还没求值）—— 正确写法是默认 `''`，dot-source 之后再 `if ($X -eq '') { $X = ... }` 回填。
3. **路径一律走 `config.ps1`**（`$WorkspaceRoot` / `$DshTts` / `$DshCache` / `$DshOut` / `$DshLogs` / `$DshShots` / `$TtsSavesDir` / `$TtsImagesDir`）；
   ⛔ **不许再出现 `C:\Users\<名字>` 这种硬编码**。
4. **改完立刻** `powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1`（补 BOM + 真解析器全量校验）。
5. **骰子读数**：`roll.ps1 -Tray <seat>` **不带 `-NoRoll` 就是"重新掷"**；只想看当前骰面必须加 `-NoRoll`。
   **对局判定以玩家报的为准**，工具读数只是复核。
6. **响应窗口**：玩家每次宣告动作 = 给我一次出牌机会 ⇒ **必须表态**（"出牌 / 不出牌"），不能当他已定型直接结算。
7. **隐藏信息双向**：不读对手隐藏区、不拿 guid 对身份；**我自己的手牌/计划也不说**。

## 已知状态（2026-10-08）

- **对局：挂起中**（2026-10-08 23:46 玩家说"结束游戏"）。续局照 `tts\docs\DICETHRONE_STATE.md` 的「恢复 / 续局三步」；
  **我 26/4 · 他 40/4**（已落账 + 回读 ✅，与 STATE「当前」块一致）· 物件 136 · 桥接 `v12-callx` · **R4 他的回合未收**。
  ⚠️ **判"玩家在不在"绝不能用 `Get-Process`**（沙箱里只看得见十几个进程，连 `TabletopSimulator` 都看不见，
  `Get-CimInstance` 直接拒绝访问）⇒ **看 39999 端口是否 LISTENING**，或直接跑 `tts\play.ps1 status`。
  （2026-10-08 我又踩了一次：靠进程表断言"玩家不在"，而 39999 明明在听 —— 规则早写在 `TTS_RULES.md`。）
- **脚本：28/28 全部通过真解析器（0 错误）**。2026-10-08 把"批量替换"事故的**两层**损坏都修完了（提交 `96dba9f`）：
  1. **语法层**：`diff_index` · `card_index` · `index_images` · `tts_api`。
     其中前两个其实**只是丢了 BOM**（中文被当 ANSI 读 ⇒ 报一堆假语法错）；
     **根因是 `check_ps1.ps1` 的 BOM 回写条件写反了**（只在已有 BOM 时才回写 ⇒ 它嘴上说 `BOM-FIXED`，实际什么也没做）。**已修**。
  2. **运行层（更隐蔽）**：`obj_index` · `bags_dump` · `install_save2` · `bootstrap` · `diff_index`
     少了"dot-source 之后回填默认路径"那一行 ⇒ **能解析、能启动，一跑就写向空路径**。
  ⇒ **新纪律：`check_ps1.ps1` 通过只证明语法对，不证明脚本能用。** 改完 `.ps1` 要确认默认值真被回填
     （每个 `''` 默认值都得有 `if ($X -eq '') { $X = ... }`）；`diff_index.ps1` 有离线自测，见 `HANDOFF.md` §6.9。
- **工作区已从 `~/.dsh` 迁出**（项目 + `cache\ out\ logs\ shots\` 都在本项目根），
  但 **`~/.dsh` 里仍留着 `archive\`**：`~\.dsh\archive\tts-legacy\`（33 个旧 `.ps1` + 各自的 README）·
  `~\.dsh\archive\system\`。⛔ 别再写"`.dsh` 只剩 harness 自己的东西"——旧脚本归档还在那儿。
