# AGENTS.md —— TTS 代玩项目宪章（本仓库根 = `$DSH_HOME`）

> 只讲**在这个仓库里怎么干活**；跨项目纪律在 `~/.dsh\AGENTS.md`。
> ⛔ 比分/待办/规则数字**都不放这里** ⇒ 放 `tts\docs\DICETHRONE_STATE.md`（唯一真源）。
> 📌 接手先读 `HANDOFF.md`（现状 · 待办）· **动手改东西前读 `tts\docs\MAINTENANCE.md`**（坑 ×13 ＋ 注入/隔离）。

## 这个项目

在 **Tabletop Simulator** 里由 AI 代打桌游：人类只做**决策** + 点「**结束回合**」，其余棋子操作全由 agent 走 TTS 消息桥接完成。
当前《王权骰铸》：玩家 = P1 Red 猩红女巫 · 我 = P2 Blue 月精灵。

## 启动（**先做，否则脚本会读写错目录**）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <本仓库>\start-agent.ps1
```

它把 `$env:DSH_HOME` 钉到本仓库根再起 dsh。环境里若残留旧值（`<用户目录>\.dsh`），脚本会静默读写一个**不存在**的目录。
验证：`tts\play.ps1 status` 应回 `bridge=v12-*`，`objs` 与桌面相符。

## 每回合只读这一份（**别整份读手册**）

`tts\docs\DICETHRONE_STATE.md` —— **现在这款 ＋ 本局状态（唯一真源：HP/CP · 状态 token · 待办 · guid）＋ 随身卡（回合步骤 · 控制台动词 · 哨兵）**；原 `CURRENT.md` / `PLAY.md` 已并入。

只在需要时查：`tts\docs\DICETHRONE_FLOW.md`（规则/骰面/伤害，顶部有路由表）· `tts\docs\TTS_RULES.md`（TTS 通用坑 ＋ **§二 工具清单**）·
`tts\docs\USER_GUIDE.md`（人怎么用）· `tts\docs\MAINTENANCE.md`（动手改东西前）。

## ⛔ 纪律

1. **改任何 `.ps1` 前先 `git commit`**；⛔ **绝不用批量字符串替换改活代码**（本仓库就这么连坏过 22 个脚本）。
2. **`param()` 必须是第一条语句**；**默认值里不许引用 config 变量**（那时还没求值）⇒ 默认 `''`，dot-source 之后 `if ($X -eq '') { $X = ... }` 回填。
3. **路径一律走 `tts\config.ps1`**（`$WorkspaceRoot/$DshTts/$DshCache/$DshOut/$DshLogs/$DshShots/$TtsSavesDir/$TtsImagesDir`）；⛔ 不许出现 `C:\Users\<名字>`。
4. **改完 `.ps1` 立刻**跑 `tts\check_ps1.ps1`（递归补 BOM + 真解析器）；**解析通过 ≠ 能用** ⇒ 再跑 `tts\tests\*.ps1`（两个离线自测，不需要 TTS）。
5. **骰子**：`roll.ps1` 必须明说 `-Roll`/`-NoRoll`（裸调用 `exit 2`，不接触 TTS）；**判定以玩家报的为准**。
6. **响应窗口**：玩家每次宣告 = 我的出牌机会 ⇒ **必须表态「出牌 / 不出牌」**。
7. **隐藏信息双向**：不读对手隐藏区、不拿 guid 对身份；**我自己的手牌/计划也不外传**（手牌在 gitignore 的 `local\hand\`）。
8. **判"玩家在不在"看 39999 端口**（`netstat -ano | findstr :39999`；⛔ `Get-NetTCPConnection` 在本沙箱里**会假报"没人在听"**）或跑 `play.ps1 status`；⛔ 别用 `Get-Process`（沙箱里根本看不见 TTS 进程）。
