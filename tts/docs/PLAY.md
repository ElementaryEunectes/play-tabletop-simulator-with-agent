# PLAY.md —— 每局开工的**随身卡**（只放"每回合都要做的事"）

> **什么时候读我**：在 `tts\docs\` 里做**任何一局**时，每回合开工第 3 步（读完 `CURRENT.md` + `<游戏>_STATE.md`）。
> **跨项目纪律**在 `~/.dsh\AGENTS.md`；**TTS 全套规则/工具/坑**在 `tts\docs\TTS_RULES.md`（**本文件不重复它们，只写"这一局要敲什么"**）。
> 规则数字在 `<游戏>_FLOW.md`，比分与待办在 `<游戏>_STATE.md`。

## 一回合的走法（照抄）

1. `CURRENT.md` → `<游戏>_STATE.md`（**唯一真源**）→ 本文件；
2. **核对盘面**：跑本局控制台的 `status`（一条命令拿实测值，别靠记忆）；
3. **该我走**：按 STATE 的"待办" ＋ FLOW 的技能/坐标 → **一条命令一个阶段**；
4. **摆决策**：玩家的选择 = 「选项 ＋ 代价」摆出来等他点（AGENTS §3；**绝不替他拍**）；
5. **表响应**：对手宣告 → 我的响应窗口 → 明说"**出牌 / 不出牌**"（TTS_RULES §三条约定）；
6. **写回 STATE**：只改"当前"块与待办，过去回合压成一行；
7. **挂哨兵**：等玩家点「结束回合」（见下），别轮询。

## 本局控制台（王权骰铸）

`tts\play.ps1 <动词>` —— **一条命令 = 一个阶段**，输出 30–80 token：

| 动词 | 作用 |
|---|---|
| `status` | 物件数 ＋ 双方 HP/CP ＋ 状态 token |
| `income -Seat moon` | 收入阶段（+1 CP；**这模组收入不抽牌**） |
| `roll -Seat moon [-Lock 1,3]` | 我的进攻掷骰（但 `setLock` 是坏的 ⇒ 见下） |
| `attack -Seat scar -Ability '<名>' [-Apply] [-Damage N]` | 判定/结算**他**的技能（不带 `-Apply` 只查表，不写任何东西） |
| `defense -Seat moon [-Apply -Incoming N]` | 我的防御判定/结算（`-Apply` 才真扣血） |
| `say -TextFile <utf8>` | 往笔记本发一行 |

⚠️ **别 read `play.ps1` 本体**（~10k token）；技能表在 `cache\dicethrone_rules.json`，卡面文本在 `cache\dicethrone_cards.md`（`tts\card.ps1 -Q '<名>'` 查）。
⚠️ **`setLock` 坏了**（`cannot convert userdata to Boolean`）⇒ **重掷只能逐颗**：`ds.ps1 -Do act:<骰guid>:roll`。
⚠️ **骰子读数**：`roll.ps1 -Tray <seat>` **默认会先掷再读**，纯读要加 **`-NoRoll`**；**骰子判定以玩家报的为准**（详见 `TTS_RULES.md` 的坑）。
⚠️ **结算顺序**：宣告 → **先问玩家改不改骰** → 防御掷骰 → 才扣血；`-Apply` 之后**必须回读**。

## 哨兵 / 叫醒（**不跨会话继承**）

- **玩家点「结束回合」是唯一的推进方式**（那个按钮我点不了，见 `TTS_RULES.md`）。
- 叫醒链：`front_watch.ps1` → `cache\front.txt`（`TURN=Pn`）→ file 哨兵 pattern `TURN=P<我的席位>`；
  笔记本链：`channel_watch.ps1` → `cache\chan.txt` → 哨兵 pattern `^NEW`。
- **新会话必须重挂**（编号每会话不同，先 `sentinel_list` 看，别照抄旧会话的 `watch-3`/`watch-5`）：
  `sentinel_watch kind=file target=<绝对路径> pattern=<正则>`，`note` 写"醒来先干什么"。
- 判活：`front.txt` / `chan.txt` 的 **mtime 秒级滚动就是心跳**（`OTHER <时:分:秒>` 也算）。**心跳在动就别重启 watcher**；
  停了几分钟才用**后台作业**重启：`front_watch.ps1 -Minutes 300` / `channel_watch.ps1 -Minutes 300 -IntervalMs 12000`。
- 收工：`sentinel_cancel` ＋ kill 后台作业（别留哨兵在旧会话里反复叫）。

## STATE 维护（这局的"当前"块）

- 体积目标 **≤ 5 KB**：只留**顶部"当前" ＋ 待办 ＋ 本局固定事实（guid）**；过去回合压成一行，长的挪 `archive\`。
- **同一时刻只允许一个写入者**：改前先 read，改后报字节数。
- ⛔ **不放规则、不放坐标常量、不放工具用法、不放纪律** —— 那些属 FLOW / TTS_RULES / AGENTS。
