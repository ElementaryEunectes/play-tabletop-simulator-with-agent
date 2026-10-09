# HANDOFF.md —— 交接简报（最近更新 2026-10-09 夜）

> **怎么读**：本文件 = "现在到哪了 + 先干什么"（**按需读，不注入**）。
> 长期规矩 ⇒ `AGENTS.md`（本项目）＋ `$DSH_HOME\AGENTS.md`（平台宪章）；改东西前 ⇒ `tts\docs\MAINTENANCE.md`；坑 ×17 ＋ 注入机制 ⇒ harness home 的 `platform\MAINTENANCE.md`。
> **文档全索引 ⇒ `tts\docs\README.md`**（那张表里没有的细节，本文件也不复述）。
> ⚠️ **先做 §1 的启动动作**，否则脚本会读写一个不存在的旧目录。

## §1 启动（必做，30 秒）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <本仓库>\start-agent.ps1   # 只做 Set-Location 到本仓库
```
- 它**只切 cwd**（= 项目链注入的前提；不动 `$DSH_HOME`、不建 profile）。本机直接 `dsh web` 也行，只要会话工作区 = 本仓库。
- ⚠️ `$DSH_HOME` **双重含义**（harness home ＋ 本工作区根）：环境里残留旧值 `<用户目录>\.dsh` ⇒ `tts\config.ps1` 解析到**已搬空的旧目录**（产物写丢、`live_index` 报 `ds.ps1 not found`）。它的解析顺序写在文件头。
- 验证：`tts\play.ps1 status`（**版本号以实际返回为准**）· 门禁 `tts\tests\run_all.ps1`。

## §2 对局状态 ⇒ **不在仓库里**

对局现状 · 续局步骤 · 已结清的规则 · 原始 guid · **待玩家拍板的规则冲突** · **卡面待补** ⇒ 全在 **`local\games\<游戏>\`**（`local\games\_current.md` 指向具体文件；`local\` 被 gitignore）。
**为什么**：本仓库只放**对任何 TTS mod 都成立**的通用工具链（判据 ⇒ `AGENTS.md`）。

## §4 待办（按优先级）

1. ✅ **D2 已完成（2026-10-09）**：`local\games\dicethrone\objects.json` 写好（8 个区块）⇒ `bootstrap.ps1` 恢复可用（`cache\session_map.md` = 92 行 / 3.9 KB；HP·CP 4 行 · 牌堆 2 · 骰子 5+5 · 英雄板 2 · 规则书 1）。
   📌 关键：**索引里同一物件常有两行**（容器副本 1523/1659）⇒ 每个区块都要 `topLevel: true`；这条已写进 `BOOTSTRAP.md` §1b 与数据文件自身的 `_note`。换英雄/换局：`bootstrap.ps1 -Inventory` 取新 hash 加一行。
   ✅ **"任何 mod 都成立"真验证已完成（2026-10-09 晚）**：用户给的第二款 mod = **七圣召唤**（`GAME=qisheng`）⇒ `install_save2.ps1 -KeepLua -KeepTabs` 烤进 `TS_Save_9.json`（模组自带的 116 KB Global 脚本与 12 页笔记本**原样保留**）⇒ 玩家重载后 **`ping` 回 `v13-turntoken`**（§7.9 第 1 条过）⇒ `obj_index.ps1 -File <绝对路径>`（625 行）⇒ `bootstrap.ps1 -Inventory`（190 nicks / 41 hashes）⇒ 写 `objects.json`（7 区块）⇒ `bootstrap.ps1` 出 **115 行地图**。
   📌 学到的两条：① **`obj_index.ps1 -File` 要绝对路径**（相对 cwd 解析，给 `TS_Save_9.json` 会报 not found）；② 这个 mod 把教学写在 **Notecard** 上（地图有专门一节 ⇒ 开局先读它，再写 `FLOW.md`）。
   ⛔ 仍然**不要**为了验证去造假的第二款游戏（fixture 只验"数据不在代码里"这条契约）。
2. 🔴 **回合令牌验收（`v13-turntoken`，未做）** ⇒ **§7.9**（要 TTS 在跑 ＋ 玩家重载存档）。
3. 🔴 **游戏侧待办**（5 条规则冲突 · 卡面文本）⇒ **`local\games\dicethrone\STATE.md`**（⛔ 不进仓库，本文件不复述）。
4. 🟡 **让第三方"简单部署 · 廉价游玩"的最后三块**：**A** `STATE`/`FLOW` 模板（新游戏起手）· **C** `setup.ps1` 向导 · **E** demo ＋ 30 秒录屏（需 TTS）。
   判据：陌生人只有**公开仓库 ＋ Windows ＋ TTS ＋ 一个 workshop mod**，能否在**一小时内**打完一回合？
5. 🟡 **开源收尾**：`LICENSE`(MIT) ✅ · `README.en.md` ✅ · 路径/隐私 ✅（树里 0 处 `C:\Users\<名字>`）· 离线门禁 **6 条** ✅ ⇒ 剩下"首次上手的时间/成本期望"写进 README 顶部。
6. ⚪ **平台层不随仓库走**（十几条坑只在 harness home）⇒ 开源用户只有 `tts\docs\MAINTENANCE.md` §0；**"等玩家点结束回合"依赖 DSH 的 sentinel**，换 agent 平台会退化成轮询。
7. ⚪ **火绒**（环境事实，不是待办）⇒ §9。

## §6 环境与坑 ⇒ 两处（本文件不复述）

- 本仓库要点（沙箱/HIPS/编码/门禁姿势）⇒ **`tts\docs\MAINTENANCE.md` §0**。
- 平台 ×17 条坑 ＋ 上下文注入与隔离 ⇒ **`platform\MAINTENANCE.md`**（旧编号 §6.8/§6.9 = 那里"校验器阳性对照"两条）。

## §7.9 回合令牌验收（`v13-turntoken`，**尚未生效**）

桥接 Lua 已加 `turn_token`/`turn_state`（自制可点令牌：点一下把回合号写进**昵称** ⇒ `diff_index.ps1` 现在也差 `nick`）。
`dsh_global.lua` 是**烤进存档**的 ⇒ 需 `install_save2.ps1` 重装 ＋ **请玩家重载**，然后逐条验：

1. `{cmd="ping"}` 的 `v` = **`v13-turntoken`**（否则存档没重装成功）。
2. `{cmd="turn_token"}` ⇒ `ok=true` · `created=true` · 记下 `guid`；**再跑一次**应 `created=false`（幂等）。
3. 玩家**点一下** ⇒ `{cmd="turn_state"}` 的 `turn` **0→1**、`nick` = `DSH-TURN 1`。（`call…fn="dshBump"` 只验我自己的簿记；mod 的回合机另说。）
4. `diff_index.ps1 -Snapshot` → 点一次 → 再跑 ⇒ 出现 **`NICK (昵称变化)`** 段且 SUMMARY 含 `nick=1`。
5. **对照**：TTS 切后台再点 ⇒ 令牌状态**照样读得到**（`front.txt` 此时读不出 `TURN`）。
6. 任一条不符 ⇒ 记下 `turn_state` 的**原始返回**与 TTS `Console` 的 Lua 报错，**别猜**。

## §8 每请求注入（摘要；机制/预算/安装 ⇒ `tts\docs\INJECTION.md`）

平台宪章 **3,950** ＋ 项目 `AGENTS.md` **3,518** ＋ 本机 `AGENTS.local.md` **2,299** ＝ **≈9.5 KB/请求**；发布时**不用手打**：`start-agent.ps1` 的一行 `$ProjectDshProfile`（或 `-DshProfile tts-agent`，即 `dsh --profile tts-agent`；⚠️ **不是** `dsh tts-agent web`）⇒ **≈5.7 KB**。机制/目录结构/装法 ⇒ **`tts\docs\INJECTION.md` §4 方案 A′**。

## §9 会话纪要（**理由全在 git 提交信息里**，这里只留结论）

- **2026-10-08**：脚本全修（BOM ＋ 真解析器 ×28）· 效率（`play.ps1 turn` 1.5s · `say.ps1` 单进程 · `AGENTS.md` 瘦身）· 官方规则书落地（`Custom_PDF` → Node 下载 → 抽页 → 索引）· 门禁与离线自测入库 · 平台层迁出仓库。
- **2026-10-09 场 1**（`d2971a8` … `adfc650`）：`nick` 纳入差分 · **回合令牌 Lua（`v13-turntoken`）** · `INJECTION.md` · 三槽去重 · 门禁改"文件输出 ＋ 成功标志" · 记下"六个门禁要在受限模式下跑"的目标。
- **2026-10-09 场 2**（`6e643c1` · `e22911d` · `2f7e5cd` · `1664441` · `ba6135d` · `98dfab2`）：
  - **D0**：diff 链去掉顶层 `exit`（改 `return`）＋ 门禁**同进程调用** ⇒ **6 条门禁在受限模式下全绿**，「需要完全权限」作废。
  - **D**：**认物数据离开代码** —— `cache\<game>_alias.json` ＋ `local\games\<游戏>\objects.json`（新增 **`-Inventory`** 半自动产出）＋ 第 6 个门禁 `test_game_data.ps1`（**否定用例**才证明"数据不在代码里"）。
- **两条实测纠正**（细节见 `tts\docs\MAINTENANCE.md` §0 / 平台宪章）：
  - **`exit`**：在**脚本文件**里被该文件自己的边界接住（`&`/`.` 调用者不死，码只进 `$LASTEXITCODE`）；只有**没有脚本边界**的 `exit`（`iex`、手贴代码）才当场结束进程 ⇒ 宪章那句**已改准确**。
  - **火绒**：命中规则 `rp_name_execcreate_powershell_hidden`，**触发者永远是 harness 自己**（`node.exe` ＋ `-NonInteractive` 隐藏起 PowerShell）；**触发条件未查明**（"叠加惯用法才触发"这条我自己的结论**已被重复实验推翻**）；**用户 20:14:04 改配置后 20+ 次调用零匹配**（时间吻合、因果未证）；已知被掐的调用带 `treatment=3`。**查法 ⇒ `MAINTENANCE.md` §0**。

## §10 关键数字（2026-10-09）

工作区文件 **3,395** · `tts\` 下 **40** 个 `.ps1` · 门禁 **6** 条（入口 `tts\tests\run_all.ps1`，要证据加 `-OutFile`）· 注入 **9.5 KB/请求**（发布 5.7 KB）。
