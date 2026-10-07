# TTS 代玩工作区（DSH × Tabletop Simulator）

在 **Tabletop Simulator** 里由 AI 代打桌游的工作区：玩家（人类）只做**决策**和点「**结束回合**」，
其余全部棋子操作由 agent 通过 TTS 的消息桥接完成。当前在打《王权骰铸》（Dice Throne）。

> ⚠️ **本仓库含"跑起来要用的东西"，不含隐私与生成物** —— 凭据/会话/日志/缓存/归档都在 `.gitignore` 里。
> 🌐 English: [`README.en.md`](README.en.md)

## 怎么读（**别整份读，按角色取**）

| 要干什么 | 读什么 |
|---|---|
| 平台纪律（跨项目，自动注入） | `AGENTS.md` |
| **做 TTS 工作**（工具地图 · 按钮 · 桥接坑 · 一句话约定） | `tts\docs\TTS_RULES.md` |
| 每局开工 | `tts\docs\CURRENT.md` → `tts\docs\<游戏>_STATE.md` → `tts\docs\PLAY.md` |
| 本局规则/技能/骰面 | `tts\docs\DICETHRONE_FLOW.md` ·
    卡面文本 `cache\dicethrone_cards.md`（`cache\` 不入库，脚本会重建/手抄） |
| 脚本清单（⭐常用 / 💤休眠 / 改名前必读的引用图） | `tts\SCRIPTS.md` |
| 换局 / 冷启动 | `tts\docs\BOOTSTRAP.md` |
| 文档与目录总索引 | `tts\docs\README.md` |
| **改完怎么验证** | `tts\check_ps1.ps1`（递归补 BOM ＋ 真解析器）→ `tts\tests\test_*.ps1`（**不需要 TTS**） |

## 跑起来需要什么

1. **Windows + PowerShell 5.1**（脚本用了 `System.Drawing`、WinRT、GDI 抓屏）。
2. **DSH**（提供哨兵与工具调用；本工作区就是 `$DSH_HOME`）。
3. **Tabletop Simulator** + 目标模组；`tts\lua\dsh_global.lua` 通过 `install_save2.ps1` 灌进存档建立桥接。

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
- ⏸ 对局处于**挂起**态，续局步骤写在 `tts\docs\DICETHRONE_STATE.md` 的「恢复 / 续局三步」一节。
- 🧾 `LICENSE` = **MIT**（见下）。

## 许可与第三方

本仓库的**代码与文档**按 **MIT** 授权（见 `LICENSE`，Copyright (c) 2026 ElementaryEunectes）。
它**不覆盖**：**Tabletop Simulator**（Berserk Games）· **《王权骰铸》/ Dice Throne** 及其卡面文本与美术（Roxley / MINDVG）·
创意工坊模组本身。`tts\docs\DICETHRONE_FLOW.md` 是**自用打牌便签**（转抄了部分卡面文字），**不含任何卡图** ——
图片与卡面文本库都在 `cache\`，不进仓库。
`tts\validate_lua.js` 依赖 **`luaparse`**（MIT），但**未随仓库分发**：`npm i luaparse`，或设 `LUAPARSE_DIR`。
