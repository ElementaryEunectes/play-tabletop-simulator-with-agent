# PLAY.md —— **通用**每回合卡（对任何 TTS mod 都成立）

> **什么时候读我**：每一回合。本文件只讲"**怎么动**"：控制台动词 · 哨兵/叫醒 · 状态页维护纪律。
> **这一局的状态**在 `local\games\<游戏>\STATE.md`（**不进仓库**）；**当前是哪一款**见 `local\games\_current.md`。
> ⛔ 规则 / 技能 / 卡面 / 比分 / guid **一律不进本文件** —— 那些是"某一款游戏"的内容。

## 通用动作（动词 · 哨兵 · 状态页维护）

> 规则/技能/骰面 = 该游戏的 `local\games\<游戏>\FLOW.md`（⛔ **不进仓库**）· TTS 通用坑与**工具清单** = `TTS_RULES.md` · **本节不重复它们**。

### 一回合（照抄）

1. **一条命令开局**：`tts\play.ps1 turn` —— 一次给齐：盘面（HP/CP/token）＋ 我的骰面（只读）＋ 可打招式 ＋ 笔记本尾条。
2. 该我走：照该游戏 `STATE.md`（`local\games\<游戏>\`）的「待办」＋ 它的 `FLOW.md` 技能表 ⇒ **一条命令一个阶段**。
3. **摆决策**：把「选项 ＋ 代价」摆给玩家等他点（⛔ 绝不替他拍）。
4. **表响应**：他每次宣告 = 我的响应窗口 ⇒ 明说"**出牌 / 不出牌**"。
5. **写回 STATE**：只改「当前」块与待办，过去回合压成一行；报字节数（≤5KB）。
6. **挂哨兵**等「结束回合」（见下），**别轮询**。

### 控制台动词（`tts\play.ps1 <动词>`，一条命令 = 一个阶段）

| 动词 | 作用 |
|---|---|
| `turn` | ⭐ 回合开局一条命令：盘面 ＋ 我的骰面 ＋ 可打招式 ＋ 笔记本尾条（**全只读**） |
| `status` | 只要盘面：物件数 ＋ 双方 HP/CP ＋ 状态 token |
| `income -Seat moon -Apply` | 收入（+1 CP；本模组收入**不抽牌**）。**不加 `-Apply` 只报"会变成几"** |
| `roll -Seat moon [-Roll] [-Lock 1,3]` | 进攻掷骰；**不加 `-Roll` 只读** |
| `attack -Seat scar -Ability '<名>' [-Apply] [-Damage N]` | 判定/结算**他**的技能（不带 `-Apply` 只查表） |
| `defense -Seat moon [-Apply -Incoming N]` | 我的防御；**不加 `-Roll` 只读** |
| `say -TextFile <utf8>` | 往笔记本发一行（中文**必须**走文件） |

⚠️ **别 read 控制层入口本体** —— 当前游戏的控制层在 `local\games\<游戏>\control\`（`play.ps1` ＋ `dice`/`rules`/`verbs` 等模块，**要改哪块就读哪块**）；仓库里的 `tts\play.ps1` 只是**分发器**（解析 `GAME=` ⇒ 把参数原样转发）。分层与契约 ⇒ `TTS_RULES.md` §二 方框。技能数据 `cache\<game>_rules.json`（= `$DshGameRules`），卡面 `tts\card.ps1 -Q '<名>'`。
⚠️ `setLock` 坏了（`cannot convert userdata to Boolean`）⇒ 重掷只能逐颗 `ds.ps1 -Do act:<骰guid>:roll`。
⚠️ **骰子**：`roll.ps1` 必须明说 `-Roll`/`-NoRoll`（裸调用 `exit 2`）；**判定以玩家报的为准**。
⚠️ **结算顺序**：宣告 → 先问他改不改骰 → 防御掷骰 → 才扣血。**数字没谈定先跑 `-Apply -WhatIf`**（打印 `WILL WRITE` 但不写）；`-Apply` 真写后脚本自己回读，不一致即 `BAD DATA`。

### 哨兵 / 叫醒（细节见 `TTS_RULES.md`；**不跨会话继承**）

- **回合交接（本仓库现行做法，2026-10-11 定稿）**：
  - **玩家侧**：按那枚 **Turn Tracker** 的按钮 ⇒ 它的**颜色簿记会推进**（我们自己读它来确认），但**棋子不会移动**（它算位置那步在本机版本失效 —— 成因 ⇒ `VALIDATION.md` **F13**，别再查）。
  - **我这侧（交回）**：`tts\tr.ps1 -To player` —— **位置 ＋ `script_state` 双写**（实测一致：回执 `tr: z=-15 state=["Brown"]`）；坐标与两侧颜色取自 `cache\<game>_turn.json`（**唯一真源**）。
  - **判定**：`tts\tools\turn_side.ps1`（读棋子 `z` 的符号）⇒ 哨兵 `command` 每 **15 s**（实际约 20 s）探一次，`pattern=TURN-CHANGED`；**别轮询**。间隔为何是这个数 ⇒ `BOOTSTRAP.md` §C。
  - ⛔ **别再用 `callx`/`Object.call` 驱动别的 mod**（会把 TTS 弄失联，两次实测）；⛔ **别在 `messageID 3` 里改别人物件的函数**（会污染它的行为，清理办法见 F13）。
  - ⚠️ 那枚棋子的 **`Name` 字段必须写着颜色顺序**（本机 `Brown Teal`）—— 这是它**文档要求**的配置；清空会让它按 10 色表轮转、跑到**空座位**。
- ⛔ **"我点不了那个按钮"的判定与理由只有一处**：`TTS_RULES.md` §四 —— **别处不要再复述**；哪天它能被按下去，只改那一处。
- 新会话**必须重挂**哨兵（编号每会话不同，先 `sentinel_list`）。
- 收工：`sentinel_cancel` ＋ kill 后台作业。

### STATE 维护

- ≤5KB · **同一时刻只允许一个写入者**（改前先 read，改后报字节数）· ⛔ 不放规则/坐标常量/工具用法。

---
