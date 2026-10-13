# USER_GUIDE.md —— 人怎么用（玩家手册）

> **什么时候读我**：第一次用、或要**拿给玩家看**的时候。给 AI 看的规矩不在这里。

> 你（人类）只需要做两件事：**做决策** 和 **点「结束回合」**。其余棋子操作由 AI 通过 TTS 桥接完成。
> 给 AI 看的规矩在 `AGENTS.md` · `PLAY.md`（通用每回合卡）＋ `local\games\<游戏>\`（该局状态，不进仓库）；装环境 / 换局 / 换模组在 `BOOTSTRAP.md`；脚本清单在 `MAINTENANCE.md` §5。

## 1. 开一局（30 秒）

**在资源管理器里双击本仓库根目录的 `start.cmd`** —— 就这样，不用敲命令。（⛔ **别直接双击 `.ps1`**：Windows 会用记事本打开它。）
没装 `dsh`（Node 全局包）时它会停下并告诉你怎么装。

> 进阶 / 排错（在 PowerShell 里手打）：`powershell -NoProfile -ExecutionPolicy Bypass -File "<本仓库>\start-agent.ps1"`
> 报"禁止运行脚本"是执行策略问题 —— 上面这行里的 `-ExecutionPolicy Bypass` 就是绕开它的正路，**不需要改机器策略**。

1. 它把**会话目录切到本仓库**（不切 ⇒ 项目的 `AGENTS.md` 根本不会注入）＋**给本项目一个独立 harness home**（链接你原有的会话与凭据，但**不放** `AGENTS.md` ⇒ **通用那份不会被注入**，也不用搬数据），然后启动 agent。
   ⚠️ 唯一**不会**发生的麻烦是"路径写错" —— `tts\config.ps1` 会自愈（这条以前是真的，现已由代码保证）。
2. 在 TTS 里**载入存档**（哪一份、叫什么，见 `local\games\_current.md`）。
3. 让 AI 跑一句自检：`tts\play.ps1 status` —— 看到 `bridge=v15-...`（版本号以实际返回为准）且 `objs` 与桌面相符就算通了。

⚠️ 若 39999 端口有人在听但 AI 说"没反应"，先确认**存档是不是载入了**（桥接脚本是**烤进存档**的，光开 TTS 不够）。

## 2. 一回合里你做什么

| 你的动作 | AI 会做什么 |
|---|---|
| 在笔记本「DSH 对话频道」里说一句话（宣告技能 / 报骰面 / 提问） | 收到后**必须表态**"出牌 / 不出牌"，并把选项与代价摆出来 |
| 点棋子 / 点牌 | 先冻结一张基线快照，再用 `diff_hidden.ps1` 读变化（**不读你的隐藏区**） |
| 点桌上那枚**回合标记**（Turn Tracker）的 End Turn 按钮 | 棋子挪到**下一个颜色的手牌位置** ⇒ 轮询器先发现（**~0.5–3.3 秒**），平台再投递（**~23 秒**，不在我们手里）⇒ 一般 **~25 秒内**我会开工 |
| ⚠️ 按了**看着没反应**时：多半是它的 `Name` 字段没填颜色顺序、或"颜色与位置"错位（**不是接口坏了** —— 以前那句"旧接口已删除"是错的）⇒ 由 AI 修 `Name`，你再**按一次**；也可能要**按两次**才换边 | 同上；⛔ 那件是 `LOCKED`（锁住），**拖不动** —— 别再试着拖它 |

⛔ **「结束回合」这件事我们程序里按不了**（TTS 不吃合成输入）—— 判定与理由、以及"要改只改哪一节"**只有一处**：`tts\docs\TTS_RULES.md` §三。
📌 2026-10-11 起：叫醒靠**棋子的位置**（`cache\turn_side.txt` ＋ file 哨兵），**不再**靠"TTS 是否在前台"（旧的 `front.txt` 那条链已停用）。

## 3. 什么时候 AI 会请你帮忙

桥接**只索引顶层物件**，下面这些它读不到，得你来：

- **容器里的牌**（手牌 / 牌堆内容）⇒ 把牌**拖到桌上**，或直接**贴张图**。
- **状态 token 的摆放**（`Infinite_Bag` 里取出的 token 常常没有图案）⇒ 请**你来放**。
- **骰面确认** ⇒ AI 会读出来给你核，**以你报的为准**。
- 卡面文字看不清 ⇒ AI 可以裁图放大（`crop_zoom.ps1`），但你贴图更快。

## 4. 在哪说话

- **游戏内**：笔记本「DSH 对话频道」。AI 写的时候只保留最近 ~600 字，更早的自动归档到 `logs\channel_archive.txt`。
- **游戏外**：`start-agent.ps1` 启动后打开的那个页面，直接说。

两处 AI 都会看。但**只有你结束回合（按那枚标记的 End Turn 按钮）它才会自动醒**（靠棋子的位置：`cache\turn_side.txt` ＋ file 哨兵）；
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
| **打字卡**（连记事本都卡） | TTS 那张**重桌子在后台仍烧 GPU**（2026-10-09 实测：647 物件的桌子 ≈**73%** GPU，空桌 ≈10%）⇒ 合成器被占，连记事本插入符都顿。修法：驱动里给 `Tabletop Simulator.exe` 设「**后台应用程序最大帧速率**」= 20 fps（NVIDIA 控制面板 → 管理 3D 设置 → 程序设置；AMD 是"后台帧率 / 帧率目标控制"）—— ⚠️ **必须重启 TTS 才套用**（实测：不重启 73%→73%；重启后 73%→**11%**）。次选：**真·最小化**（不是 alt+tab，切窗口≠停止渲染）· 降分辨率/关 VSync · 换空桌 `Menu → New Game`。⛔ 别去关模组功能（它 648 个脚本里 **0 个 `function update(`**，不是脚本的锅） |
| **打字不方便，想用嘴说** | DSH **自带实验性语音输入**：`@deepseek-ai/dsh-experimental-voice-input-bundle`（内含客户端麦克风按钮 `client-ui-voice-input` ＋ STT `speech-to-text`，含 **SenseVoice** 后端）。开法：设置 → **Plugins/插件** 里启用；或命令行 `dsh plugin --profile web add @deepseek-ai/dsh-experimental-voice-input-bundle`（⚠️ `dsh plugin` **必须带 `--profile <名字>`**，不加直接报错）；或往 `~\.dsh\profiles\web\package.json` 的 `dsh.profile.bundles` 加一行 `@deepseek-ai/dsh-experimental-voice-input-bundle` 后重启 `dsh web`。⚠️ 名字里写着 experimental（可能要额外配置/模型） |

## 6. 什么会动你的桌面 / 存档

- **桌面（HP / CP / token / 骰子）**：只有 `play.ps1` 的写动词会改，而且**每个都要显式开关**：
  `attack`/`defense`/`income` 要 `-Apply`，`roll` 要 `-Roll`。**写完必然回读**，不一致即 `BAD DATA` 停。
  想先看不写：任何写动词加 **`-WhatIf`** ⇒ 打印 `WILL WRITE ...` 但**一个字节都不写**。
- **存档文件**：只有 `install_save2.ps1` 会写（换局 / 装桥接时用，带 `-DryRun`）。**打牌期间 AI 不写存档** —— 存档由你在游戏内保存。
- **纯只读**：`status` · `turn` · `roll.ps1 -NoRoll` · `diff_hidden` · `live_index` · `card.ps1` · 两个离线自测。

## 7. 想自己核一遍（**不需要开 TTS**）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\run_all.ps1   # 8 条门禁一起跑（"退出码 0 ＋ 输出含成功标志"才算过）
```
逐条清单/限制 ⇒ `CONTRIBUTING.md` §3；本机沙箱注意事项 ⇒ `MAINTENANCE.md` §0。
