# AGENTS.md —— TTS 代玩项目宪章（**本仓库**）

> 只讲**在这个仓库里怎么干活**；跨项目纪律在 `$DSH_HOME\AGENTS.md`（平台宪章，本机**照旧注入**；发布/开源时可用 `dsh tts-agent web` 屏蔽 ⇒ `tts\docs\INJECTION.md` §4 变体）。
> ⛔ **具体某一款游戏的东西**（比分/待办/规则/卡面/卡库/牌）**不进仓库** ⇒ 放 `local\games\<游戏>\`（唯一真源在那里）。
> 📌 接手先读 `HANDOFF.md`（现状 · 待办）· **动手改东西前读 `tts\docs\MAINTENANCE.md`**（本仓库要点；坑在 harness home 的 `platform\`）。

## 这个项目（⭐ **开源的边界**）

在 **Tabletop Simulator** 里由 AI 代打桌游：人类只做**决策** + 点「**结束回合**」，其余棋子操作全由 agent 走 TTS 消息桥接完成。

⭐ **本仓库 = 对「任何 TTS mod」都适用的通用工具链**＝ **开源内容**。
⛔ **某款游戏专属的东西不进仓库**：状态/比分 · 规则与卡面 · 卡库 · 牌与计划 · 当前在玩哪款 ⇒ 一律放 **`local\games\<游戏>\`**（`local\` 在 `.gitignore` 里）。
**一句话判据**：**换个 mod 还成立 ⇒ 留下；只对这一局成立 ⇒ 搬进 `local\`。**

## 启动（**在本仓库里起 dsh**）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <本仓库>\start-agent.ps1
```

它只做一件必要的事：**把 cwd 切到本仓库**（否则项目链不注入本文件）；`$DSH_HOME` **不用动**。
验证：`tts\doctor.ps1`（应列出 **平台宪章 ＋ 项目 ＋ overlay**）· `play.ps1 status` 能通且 `objs` 与桌面相符。
👤 **给人用**：让他双击 `start.cmd`（⛔ `.ps1` 会进记事本）。

## 每回合读什么（**别整份读手册**）

1. **`local\games\<当前游戏>\STATE.md`** —— **这一局的状态**（唯一真源：比分 · token · 待办 · guid）· ⛔ **不进仓库**
2. **`tts\docs\PLAY.md`** —— **通用**每回合卡（控制台动词 · 哨兵 · 状态页维护）· ✅ 在仓库里

当前哪款 ⇒ `local\games\_current.md`；按需：`tts\docs\TTS_RULES.md`（开工前一次）· `tts\docs\MAINTENANCE.md`（**改东西前**）· `tts\docs\BOOTSTRAP.md`（换 mod）· `tts\docs\USER_GUIDE.md`（人怎么用）。

## ⛔ 纪律

1. **改任何 `.ps1` 前先 `git commit`**；⛔ **绝不用批量字符串替换改活代码**（为什么 + 替代做法 ⇒ `CONTRIBUTING.md` §4）。
2. **`param()` 必须是第一条语句**；**默认值里不许引用 config 变量**（那时还没求值）⇒ 默认 `''`，dot-source 之后回填（`test_param_backfill` 门禁在查）。
3. **路径与隐私**：走 `tts\config.ps1`（变量都在那份）；⛔ **绝对路径/用户名不许进受跟踪文件**（`instruction hygiene` 门禁在查）。
4. **改完 `.ps1`**：`tts\check_ps1.ps1`＋`tts\tests\run_all.ps1`（唯一入口，7 条；**解析通过 ≠ 能用**，判定 ⇒ `CONTRIBUTING.md` §3）。
5. **骰子**：`roll.ps1` 必须明说 `-Roll`/`-NoRoll`（裸调用 `exit 2`）；**判定以玩家报的为准**。
6. **响应窗口**：玩家每次宣告 = 我的出牌机会 ⇒ **必须表态「出牌 / 不出牌」**。
7. **隐藏信息双向**：不读对手隐藏区、不拿 guid 对身份；**我自己的手牌/计划也不外传**（手牌在 `local\games\<游戏>\MYHAND.md`；`local\` 不进仓库）。
8. **判"玩家在不在"**：跑 `tts\play.ps1 status`（端口等平台手段见 `tts\docs\MAINTENANCE.md` §0）。
