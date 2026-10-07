# PLAY.md —— **通用**每回合卡（对任何 TTS mod 都成立）

> **什么时候读我**：每一回合。本文件只讲"**怎么动**"：控制台动词 · 哨兵/叫醒 · 状态页维护纪律。
> **这一局的状态**在 `local\games\<游戏>\STATE.md`（**不进仓库**）；**当前是哪一款**见 `local\games\_current.md`。
> ⛔ 规则 / 技能 / 卡面 / 比分 / guid **一律不进本文件** —— 那些是"某一款游戏"的内容。

## 通用动作（动词 · 哨兵 · 状态页维护）

> 规则/技能/骰面 = `DICETHRONE_FLOW.md` · TTS 通用坑与**工具清单** = `TTS_RULES.md` · **本节不重复它们**。

### 一回合（照抄）

1. **一条命令开局**：`tts\play.ps1 turn` —— 一次给齐：盘面（HP/CP/token）＋ 我的骰面（只读）＋ 可打招式 ＋ 笔记本尾条。
2. 该我走：照 `DICETHRONE_STATE.md` 的「待办」＋ FLOW 的技能表 ⇒ **一条命令一个阶段**。
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

⚠️ **别 read `play.ps1` 本体**（35KB ≈ 10k token）；技能表在 `cache\dicethrone_rules.json`，卡面 `tts\card.ps1 -Q '<名>'`。
⚠️ `setLock` 坏了（`cannot convert userdata to Boolean`）⇒ 重掷只能逐颗 `ds.ps1 -Do act:<骰guid>:roll`。
⚠️ **骰子**：`roll.ps1` 必须明说 `-Roll`/`-NoRoll`（裸调用 `exit 2`）；**判定以玩家报的为准**。
⚠️ **结算顺序**：宣告 → 先问他改不改骰 → 防御掷骰 → 才扣血。**数字没谈定先跑 `-Apply -WhatIf`**（打印 `WILL WRITE` 但不写）；`-Apply` 真写后脚本自己回读，不一致即 `BAD DATA`。

### 哨兵 / 叫醒（细节见 `TTS_RULES.md`；**不跨会话继承**）

- 推进只有一条路：**玩家点「结束回合」**（我点不了）⇒ 我靠 file 哨兵盯 `cache\front.txt` 的 `TURN=P2` 被叫醒。
- 新会话**必须重挂**（编号每会话不同，先 `sentinel_list`）：`sentinel_watch kind=file target=<绝对路径> pattern=<正则>`；另一条盯 `cache\chan.txt` 的 `^NEW`。
- 判活 = 两个 txt 的 **mtime 秒级滚动**；**停了才**后台重启 `front_watch.ps1 -Minutes 600` / `channel_watch.ps1 -Minutes 600 -IntervalMs 12000`。
- 收工：`sentinel_cancel` ＋ kill 后台作业。

### STATE 维护

- ≤5KB · **同一时刻只允许一个写入者**（改前先 read，改后报字节数）· ⛔ 不放规则/坐标常量/工具用法。

---
