# STATE.md —— <游戏> · 对局状态（**唯一真源**）· ⛔ 不进仓库

> **只写"现在是什么 + 待办"**。规则/卡面/坐标 ⇒ 同目录 `FLOW.md`；手牌/隐藏信息 ⇒ `MYHAND.md`。
> 通用每回合动作（控制台动词 · 哨兵 · 状态页维护）⇒ `tts\docs\PLAY.md`；通用 TTS 规则 ⇒ `tts\docs\TTS_RULES.md`。
> 📌 本文件与 `local\` 都不进仓库 ⇒ **这里可以写游戏名、卡名、坐标**（仓库里不行）。

## 当前

**<日期>：<一句话：现在到哪了、轮到谁>。**

| | 说明 |
|---|---|
| 桥接 | <存档槽 · `ping` 回的版本号 · 物件数> |
| 认物数据 | <`objects.json` 区块数 · `cache\session_map.md` 行数> |
| 卡库 | <`cache\<游戏>_cards.md` 张数，或"未建"> |
| 规则 | <`FLOW.md` 确认了几条 / 还缺什么> |
| 回合交接 | <校准档 `cache\<游戏>_turn.json` · 判定 `tts\tools\turn_side.ps1` · 交还 `tts\tr.ps1 -To player`> |
| 对局 | <未开始 / 第 N 回合 / 挂起> |

## 本局固定事实（guid · 换局即作废）

| | 值 | 来源 |
|---|---|---|
| 我的座位 | <颜色> | <玩家告知 / `play.ps1 status`> |
| 玩家座位 | <颜色> | 同上 |
| 关键容器 | <guid 与用途> | `tts\ds.ps1 -Do container:<guid>` |
| 回合标记 | <guid> | `cache\<游戏>_turn.json` |

## 续局 / 起手步骤（照 `tts\docs\BOOTSTRAP.md` §2）

1. <玩家：在 TTS 里让 mod 内容上桌 ⇒ Save Game>
2. <`tts\install_save2.ps1 -SourceFile <那档> -KeepLua -KeepTabs -SlotName <槽位>`（先 `-DryRun`）>
3. <玩家重载那个槽位 ⇒ `tts\ds.ps1 -Do ping` 验版本号>
4. <`tts\play.ps1 status` 看桥接／玩家／轮到谁>

## 待办

1. <可勾选的条目；做完的留成 ✅ 一行，别删（后人靠它判断哪些已验过）>
2. ⛔ **不必做**：<明确写出"哪些事是故意不做的"，免得后人返工>
