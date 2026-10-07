# USER_GUIDE.md —— 人怎么用（玩家手册）

> **什么时候读我**：第一次用、或要**拿给玩家看**的时候。给 AI 看的规矩不在这里。

> 你（人类）只需要做两件事：**做决策** 和 **点「结束回合」**。其余棋子操作由 AI 通过 TTS 桥接完成。
> 给 AI 看的规矩在 `AGENTS.md` · `PLAY.md`（通用每回合卡）＋ `local\games\<游戏>\`（该局状态，不进仓库）；装环境 / 换局 / 换模组在 `BOOTSTRAP.md`；脚本清单在 `TTS_RULES.md` §二。

## 1. 开一局（30 秒）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <本仓库>\start-agent.ps1
```

1. 它先把工作区根钉好，再启动 agent。
2. 在 TTS 里**载入存档**（当前是 `TS_Save_7.json`）。
3. 让 AI 跑一句自检：`tts\play.ps1 status` —— 看到 `bridge=v12-callx` 且 `objs` 与桌面相符就算通了。

⚠️ 若 39999 端口有人在听但 AI 说"没反应"，先确认**存档是不是载入了**（桥接脚本是**烤进存档**的，光开 TTS 不够）。

## 2. 一回合里你做什么

| 你的动作 | AI 会做什么 |
|---|---|
| 在笔记本「DSH 对话频道」里说一句话（宣告技能 / 报骰面 / 提问） | 收到后**必须表态**"出牌 / 不出牌"，并把选项与代价摆出来 |
| 点棋子 / 点牌 | 先冻结一张基线快照，再用 `diff_hidden.ps1` 读变化（**不读你的隐藏区**） |
| 点右上角 **「结束回合」** | 自动醒，进入下一回合 |

⛔ **「结束回合」只能你点** —— AI 点不了（合成点击对该按钮无效，已定案）。

## 3. 什么时候 AI 会请你帮忙

桥接**只索引顶层物件**，下面这些它读不到，得你来：

- **容器里的牌**（手牌 / 牌堆内容）⇒ 把牌**拖到桌上**，或直接**贴张图**。
- **状态 token 的摆放**（`Infinite_Bag` 里取出的 token 常常没有图案）⇒ 请**你来放**。
- **骰面确认** ⇒ AI 会读出来给你核，**以你报的为准**。
- 卡面文字看不清 ⇒ AI 可以裁图放大（`crop_zoom.ps1`），但你贴图更快。

## 4. 在哪说话

- **游戏内**：笔记本「DSH 对话频道」。AI 写的时候只保留最近 ~600 字，更早的自动归档到 `logs\channel_archive.txt`。
- **游戏外**：`start-agent.ps1` 启动后打开的那个页面，直接说。

两处 AI 都会看。但**只有你在 TTS 窗口里点「结束回合」，它才会自动醒**（靠 `cache\front.txt` 的 `TURN=P2` 哨兵）；
只在外面的页面说话时，加一句"看一下"就行。

## 5. 常见问题

| 现象 | 原因 / 怎么办 |
|---|---|
| AI 半天没反应 | 看 39999 端口在不在：`netstat -ano | findstr :39999`（⚠️ **别用 `Get-NetTCPConnection`**，它在沙箱里会假报"没人在听"）。看不到 = TTS 没开或存档没载入 |
| AI 回的是**乱码** | 中文**必须走文件**：让它用 `say.ps1 -MessageFile <utf8 文件>`，别用命令行参数（控制台代码页会毁掉中文） |
| 我的骰子被重掷了 | 旧版 `roll.ps1` 默认会掷（曾连掷你 4 次）。**2026-10-08 已加护栏**：必须 `-Roll` 才掷，`-NoRoll` 只读，裸调用直接 `exit 2` 且不接触 TTS |
| HP/CP 数字对不上 | AI 每次写都会**回读并打印**，不一致就报 `BAD DATA` 停下。**以你看到的牌面为准**，它会把台账对齐 |
| 想暂停 / 收工 | 说"结束游戏"：它会撤哨兵、停后台 watcher，并把现状封存进该游戏的 `local\games\<游戏>\STATE.md` |
| 想换游戏 / 换模组 | 照 `BOOTSTRAP.md` 走（三种情形 ＋ 共同核心四步） |
| 想让它少花点 token / 快一点 | 每回合开局让它用**一条命令** `tts\play.ps1 turn`（盘面＋骰面＋招式＋笔记本尾条一次给齐） |

## 6. 什么会动你的桌面 / 存档

- **桌面（HP / CP / token / 骰子）**：只有 `play.ps1` 的写动词会改，而且**每个都要显式开关**：
  `attack`/`defense`/`income` 要 `-Apply`，`roll` 要 `-Roll`。**写完必然回读**，不一致即 `BAD DATA` 停。
  想先看不写：任何写动词加 **`-WhatIf`** ⇒ 打印 `WILL WRITE ...` 但**一个字节都不写**。
- **存档文件**：只有 `install_save2.ps1` 会写（换局 / 装桥接时用，带 `-DryRun`）。**打牌期间 AI 不写存档** —— 存档由你在游戏内保存。
- **纯只读**：`status` · `turn` · `roll.ps1 -NoRoll` · `diff_hidden` · `live_index` · `card.ps1` · 两个离线自测。

## 7. 想自己核一遍（**不需要开 TTS**）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1                   # 全部脚本：补 BOM + 真解析器
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_diff_index.ps1       # 快照差分链的离线自测
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_param_backfill.ps1   # 默认值回填自测
```
