# TTS 代玩工作区（DSH × Tabletop Simulator）

在 **Tabletop Simulator** 里由 AI 代打桌游的工作区：玩家（人类）只做**决策**和点「**结束回合**」，
其余全部棋子操作由 agent 通过 TTS 的消息桥接完成。当前在打《王权骰铸》（Dice Throne）。

> ⚠️ **本仓库含"跑起来要用的东西"，不含隐私与生成物** —— 凭据/会话/日志/缓存/归档都在 `.gitignore` 里。

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

## 已知状态

- ✅ **26 个脚本解析通过**，游戏链路（`ds.ps1 ping` / `play.ps1 status` / `roll.ps1 -NoRoll` / `live_index.ps1` / `diff_hidden.ps1`）实测可用。
- ❌ **2 个待修**（不影响打牌）：`tts\index_images.ps1`（建图索引，一次性）· `tts\tts_api.ps1`（External Editor API 退路）。
  两者的头部说明与用法都还在，照着重写即可。
- ⏸ 对局处于**挂起**态，续局步骤写在 `tts\docs\DICETHRONE_STATE.md` 的「恢复打法」一节。
