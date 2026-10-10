# AGENTS.md —— TTS 代玩项目宪章（**本仓库**）

> 跨项目纪律 ⇒ 平台宪章。接手先读 `HANDOFF.md`；**改东西前读 `tts\docs\MAINTENANCE.md`**。⛔ 游戏专属内容 **不进仓库** ⇒ `local\games\<游戏>\`。

**这个项目**：在 **Tabletop Simulator** 里由 AI 代打桌游 —— 人只做**决策**＋点「结束回合」，其余操作由 agent 走 TTS 消息桥接。
**本仓库 = 对任何 TTS mod 都适用的通用工具链**（开源内容）。**判据：换个 mod 还成立 ⇒ 留下；只对这一局成立 ⇒ 搬进 `local\`。**

**启动**：`powershell -NoProfile -ExecutionPolicy Bypass -File <本仓库>\start-agent.ps1`（只把 cwd 切到本仓库，否则项目链不注入本文件）。验证 `tts\doctor.ps1` · `tts\play.ps1 status`；给人用 ⇒ 双击 `start.cmd`。

**每回合读**：① `local\games\<游戏>\STATE.md`（本局唯一真源）② `tts\docs\PLAY.md`（通用每回合卡）。当前哪款 ⇒ `local\games\_current.md`；按需 `TTS_RULES` · `MAINTENANCE`（改前）· `BOOTSTRAP`（换 mod）· `USER_GUIDE`。

**⛔ 纪律**
1. 改任何东西前先 `git commit`；⛔ 不批量字符串替换改活代码（⇒ `CONTRIBUTING.md` §4）。
2. `param()` 是第一句；默认值不许引用 config 变量 ⇒ 默认 `''`，dot-source 后回填（`test_param_backfill`）。
3. 路径/隐私走 `tts\config.ps1`；⛔ 绝对路径/用户名不进受跟踪文件（`instruction hygiene`）。
4. 改完 `.ps1` ⇒ `tts\check_ps1.ps1` ＋ `tts\tests\run_all.ps1`（唯一入口 7 条；解析过 ≠ 能用）。
5. 骰子：`roll.ps1` 必须明说 `-Roll`/`-NoRoll`；判定以玩家报的为准。
6. 玩家每次宣告 = 我的出牌机会 ⇒ 必须表态「出牌 / 不出牌」。
7. 隐藏信息双向：不读对手隐藏区、不拿 guid 对身份；我的手牌/计划也不外传（⇒ `local\games\<游戏>\MYHAND.md`）。
8. 判玩家在不在 ⇒ `tts\play.ps1 status`。
