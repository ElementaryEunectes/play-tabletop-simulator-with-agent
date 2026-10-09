# HANDOFF.md —— 交接简报（最近更新 2026-10-09 夜 · F8 已定案）

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

0. ✅ **F8 已定案并修好（2026-10-09）**：`players` / `take` / `spawn` / `destroy` 在活体上**不是"名字是 nil"那么简单** ——
   v14 那段原语被**拼接进了 `setCount()` 的中间**（插在它最后一条语句和它自己的 `return out` / `end` 之间）⇒
   `setCount` 的收尾被甩到 `DSH_destroy` 之后，而**从拼接点起的一切都变成了 `setCount` 的函数体**，加载时从不执行。
   少一个 `end`、尾巴多一个 ⇒ **总数平衡 ⇒ 照样编译、命令照样注册**，只是引用的名字从没被赋值。
   ⇒ 根因/证据链/为什么 7 条门禁全绿也看不见它 ⇒ **`tts\docs\VALIDATION.md` F8**；工具 ⇒ `tts\docs\MAINTENANCE.md` §1a。
   ✅ 仓库侧已修（`tts\lua\dsh_global.lua`）＋ `verify_f8.js` 阴性对照通过 ＋ **门禁新增"整块加载"一步**。
   📊 **活体验收（2026-10-09 23:11 载入 `TS_Save_11.json`，3/4 过）**：
      ✅ `ping` = `v15-tags-snap-hand`（重烤生效）· ✅ `players` ⇒ `ok count=2` ＋ 每座位一行 ·
      ✅ `take` 缺卡 ⇒ `no container with guid ...`（**不再 nil 崩溃**）· ✅ `destroy` 幽灵 ⇒ `no object with guid ...`
      ⛔ `spawn` ⇒ `attempt to concatenate a nil value`（**又抓出两个缺陷**，均已修、见下）
   🐞 **活体又抓出两个缺陷**（都是"命令本身通不了"，与拼接无关）：① `spawn:type` 把 **Lua 表**塞给了
      `spawnObjectJSON`（文档：`spawnObject({type=...})` 与 `spawnObjectJSON(jsonString)` **是两个调用**）⇒ 它回 nil、却报成"需要 TTS v13.2+"；
      ② **`S(v)` 对 nil 返回 nil** ⇒ 所有 `"..." .. S(x)` 在**要报错的那种值**上当场崩 —— 报错路径自己死了比没有报错路径更糟。
      ⇒ 都已修 ＋ 离线补上 `spawn by type` 用例（阴性对照已验）⇒ `VALIDATION.md` F7。
   ⚠️ **那次 `spawn` 探测把 TTS 打挂了**（探测前 ping 正常，之后 API 直接不可达、进程还占着 `Player.log`）
      ⇒ **`spawn` 以后一条一条探**，别连着发。
   ▶ **下一步**：重启 TTS ⇒ 载入 **`TS_Save_11.json`**（已含三处修复：拼接 · `S(nil)` · `spawnObject`）⇒ 验 `spawn` ＋ **§7.9 回合令牌**。
   📌 已顺带修好并活体验过的：`container:<guid>` ⇒ 列出容器内物件的 `guid|名称|昵称|数量|牌面文本(截60字)`。
   ⚠️ 根因是 **`getObjects()` 返回纯 Lua 表、没有方法**（字段直接读 `x.guid/x.name/x.description`）。
   ⇒ 这也是**卡库的来源**（`description` 就是整张牌面），不必再手抄。

1. ✅ **D2 已完成（2026-10-09）**：**对局型 mod** 的 `local\games\<游戏>\objects.json` 写好（8 个区块）⇒ `bootstrap.ps1` 恢复可用（`cache\session_map.md` = 92 行 / 3.9 KB；HP·CP 4 行 · 牌堆 2 · 骰子 5+5 · 英雄板 2 · 规则书 1）。
   📌 关键：**索引里同一物件常有两行**（容器副本 1523/1659）⇒ 每个区块都要 `topLevel: true`；这条已写进 `BOOTSTRAP.md` §1b 与数据文件自身的 `_note`。换英雄/换局：`bootstrap.ps1 -Inventory` 取新 hash 加一行。
   ⚠️ **"任何 mod 都成立"：第二款 mod 实测 = 半过（2026-10-09 晚，详情见 `tts\docs\VALIDATION.md`）**：**非对局型** mod（自带 116 KB Global 脚本 ＋ 12 页笔记本）⇒ `install_save2.ps1 -KeepLua -KeepTabs` 烤进存档、模组自带脚本**原样保留** ⇒ 玩家重载后 **`ping` 回 `v13-turntoken`** ⇒ `obj_index.ps1 -File <绝对路径>`（625 行）⇒ `bootstrap.ps1 -Inventory`（190 nicks / 41 hashes）⇒ 写 `objects.json`（7 区块）⇒ **115 行地图**。
   🟢 这一路**全过**（传话 · 存档侧索引 · 认物 · 地图）。🔴 但 **`play.ps1` 在这款上 FAIL**（`NO PART`：它要 `cache\<game>_rules.json` 且 `status` 也走 `$Rules.dice/seats`）⇒ **这条缺陷已写进 `TTS_RULES.md` §二 方框**；"通用"目前**只是这一路证据，不是全链证据**。
   📌 学到的两条：① **`obj_index.ps1 -File` 要绝对路径**（相对 cwd 解析，给裸文件名会报 not found）；② 这类 mod 把教学写在 **Notecard** 上（地图有专门一节 ⇒ 开局先读它，再写 `FLOW.md`）。
   ⛔ 仍然**不要**为了验证去造假的第二款游戏（fixture 只验"数据不在代码里"这条契约）。
2. 🔴 **重烤存档 ⇒ 一次活体验收（仍未做）**：**F8 那 4 条**（见 §4 第 0 条）＋ **回合令牌 `v15-tags-snap-hand`**（⇒ **§7.9**）。
   两件事都已在 `TS_Save_10.json` 里，所以要**一起去验**（要 TTS 在跑 ＋ 玩家重载存档）。⛔ 重烤前那 4 条一律按**活体不可用**对待。
3. 🔴 **游戏侧待办**（5 条规则冲突 · 卡面文本）⇒ **当前游戏的 `local\games\<游戏>\STATE.md`**（⛔ 不进仓库，本文件不复述）。
4. 🟡 **让第三方"简单部署 · 廉价游玩"的最后三块**：**A** `STATE`/`FLOW` 模板（新游戏起手）· **C** `setup.ps1` 向导 · **E** demo ＋ 30 秒录屏（需 TTS）。
   判据：陌生人只有**公开仓库 ＋ Windows ＋ TTS ＋ 一个 workshop mod**，能否在**一小时内**打完一回合？
5. 🟡 **开源收尾**：`LICENSE`(MIT) ✅ · `README.en.md` ✅ · 路径/隐私 ✅（树里 0 处 `C:\Users\<名字>`）· 离线门禁 **7 条** ✅ ⇒ 剩下"首次上手的时间/成本期望"写进 README 顶部。
6. ⚪ **平台层不随仓库走**（十几条坑只在 harness home）⇒ 开源用户只有 `tts\docs\MAINTENANCE.md` §0；**"等玩家点结束回合"依赖 DSH 的 sentinel**，换 agent 平台会退化成轮询。
7. ⚪ **火绒**（环境事实，不是待办）⇒ §9。

## §6 环境与坑 ⇒ 两处（本文件不复述）

- 本仓库要点（沙箱/HIPS/编码/门禁姿势）⇒ **`tts\docs\MAINTENANCE.md` §0**。
- 平台 ×17 条坑 ＋ 上下文注入与隔离 ⇒ **`platform\MAINTENANCE.md`**（旧编号 §6.8/§6.9 = 那里"校验器阳性对照"两条）。
- **TTS 桌子本身的开销**（2026-10-09 实测）：重桌子在**后台**仍烧 GPU（647 物件 ≈**73%** vs 空桌 ≈10%）⇒ 拖慢**整机输入**（连记事本都卡，而 CPU 只 10–20%）。修法 = 驱动「**后台应用程序最大帧速率**」20 fps，⚠️ **要重启 TTS 才套用**（不重启 73→73；重启后 73→**11%**）。**用嘴代替手**：DSH **自带**实验性语音输入 `@deepseek-ai/dsh-experimental-voice-input-bundle`（客户端麦克风按钮 ＋ SenseVoice STT）。两条都写在 **`tts\docs\USER_GUIDE.md` §5 常见问题**（面向人，本文件不复述步骤）。

## §7.9 回合令牌验收（`v15-tags-snap-hand`，**已烤进存档、待验**）

桥接 Lua 已加 `turn_token`/`turn_state`（自制可点令牌：点一下把回合号写进**昵称** ⇒ `diff_index.ps1` 现在也差 `nick`）。
`dsh_global.lua` 是**烤进存档**的 ⇒ 需 `install_save2.ps1` 重装 ＋ **请玩家重载**，然后逐条验：

1. `{cmd="ping"}` 的 `v` = **`v15-tags-snap-hand`**（否则存档没重装成功）。
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

- **2026-10-09 场 3**（**验证转向**：目标从"打游戏"改成"验项目"）：
  - **通用性首次有了反例**：第二款真 mod（**非对局型**）⇒ 传话/存档/索引/认物/地图**全过**，`play.ps1` **FAIL**。
    ⇒ 逐层台账（断言 · 证据 · **未验就写未验**）＝ **`tts\docs\VALIDATION.md`**；`play.ps1` 的边界写进 `TTS_RULES.md` §二 方框。
  - **硬线落地**：受跟踪文件里 **0 处真游戏名**（唯一例外 = 两个 README 的授权声明）⇒ 门禁 `test_agents_hygiene.ps1` 新增扫描 ＋ **4 条自检**（看见植入名 / 分支数 / 条目数 / 除 BOM 外纯 ASCII）。上线即抓出 **14 个文件**的违规。
  - ⚠️ **这次"假绿"抓了两回**：① 淘汰名单写成 `@('a' + 'b', 'c' + 'd')` ⇒ 数组只有 1 个元素、正则**没有 `|`**、扫描器全瞎，而阳性对照因为**用同一个坏串**照样 PASS；② 后来一次合并编辑**吃掉一行** ⇒ 某个名字悄悄不再被扫（分支数检查 7/7 也照样 PASS）⇒ 补"条目数必须等于 N"。
  - ⚠️ **真事故两条**（⇒ `MAINTENANCE.md` §0/§4）：**丢 BOM → 工具壳按 ANSI 读 → 语法错 → `check_ps1` 把乱码固化**；**编辑工具把 `dsh_global.lua` 行尾归一**（2 行注释变 95 增 95 删，靠 `git diff --numstat` 抓出并重做）。
- **2026-10-09 场 4**（**目标重定义 + 分层落地**）：
  - ⭐ **责任边界改了**：我们**不做**"能照着打任何一款的控制层"（那东西不存在）；我们交付 **①TTS 原语的通用层** ＋ **②用户低成本"教出"某一款控制层的规程**。
    ⇒ 判据随之变成两问：**原语覆盖够不够** · **教一款快不快**。`play.ps1` 不可通用**不再是缺陷**（`VALIDATION.md` F1 已重新定性）。
  - **分层落到目录**：`tts\` = 通用层（＋ `tts\lib\bridge.ps1` 传输包装）；`tts\play.ps1` = **分发器**（纯 ASCII、无游戏知识）；
    某款的控制层（`play`/`dice`/`rules`/`verbs`）**移出仓库** ⇒ `local\games\<游戏>\control\`（`local\` 被 gitignore ⇒ 公开树里真的没有了）。
    新路径由 `config.ps1` 提供：`$DshGameControl` · `$DshLibTtslib` · `$DshLibBridge`。**教法 ⇒ `BOOTSTRAP.md` §2b**（新增）。
  - **待办重心转移**：`VALIDATION.md` **F6** ＝ 原语缺口清单（`takeObject` 点名取牌 · `spawnObject` 造物 · `getPlayers` 座位权威 —— 这三条是"教得动"的硬前提）；**F2**（翻牌朝向只在一张桌标定过）仍需复验。
  - 📌 两条"设计坑"记下来了：`ValueFromRemainingArguments` 会**吞掉位置动词**（改用 `$args`）；dot-source 会**改写 `$PSCommandPath`**（控制层的 BOM 自检必须在 dot-source **之前**捕获自己的路径，否则误报）。
- **2026-10-09 场 5**（**补 F6 原语缺口**）：
  - **桥接升到 `v14-primitives`**：新增 `players`（座位权威：谁/什么颜色/手牌数/**轮到谁**）· `take`（取**指定** CardID 那张，非顶张）· `spawn`（`json` ／ `copyguid` 复制 ／ 纯 `type`）· `destroy` · `player`（TTS 自带回合标记 / 盲挡）。
    入口也接上了：`ds.ps1 -Do 'players' | 'take:<堆>:<CardID>:<x>:<y>:<z>' | 'destroy:<g>' | 'spawn:copy:<g>:<x>:<y>:<z>' | 'spawn:type:<类型>:<x>:<y>:<z>' | 'player:<Color>:<turn|blind>'`（spawn 的完整 JSON 走 `-Json`）。
  - ⚠️ **要生效必须先重烤存档**：桥接烤在存档里 ⇒ 现在跑着的 TTS 是 v13，新命令回 **`no handler for cmd=players`**（实测）。
  - **第 7 条门禁 `bridge primitives (Lua)`**：本机没有 lua 二进制 ⇒ 装 **fengari**（JS 里的 Lua VM），把**从真文件抽取**的代码块放进桩 TTS 环境真跑 —— **16 条用例**，含"缺卡/幽灵容器必须报错而不是静默"。⚠️ 已装依赖在 `local\scratch\luatest`（不进仓库）⇒ 新机器要按 `MAINTENANCE.md` §1 装一次；**缺它 = NOT RUN，不是 PASS**。
  - ⛔ **仍缺**：`cut`/`paste`/`drop`（已进 `act` 白名单但**未验**）· `copy`/交易（**无文档 API**）；**活体验证（F7）**要在重烤后把 v14/v15 各跑一次。
- **2026-10-09 场 6**（**把 F6 剩下的补齐**）：
  - 桥接升到 **`v15-tags-snap-hand`**：`container`（列出 Bag/Deck 内容＋数量＋tags）· `hand` 的新动作 `holding`/`give`/`draw`（**摸牌进手**：`Deck.deal`，非牌堆回落 `dealToColorWithOffset`）· `act` 新增 `setTags`/`addTag`/`removeTag`/`hasTag`/`hasAnyTag`/`hasMatchingTag`（**数组参数**，`value=标签1+标签2` 或 `list`）· `setSnapPoints`（`value=x,y,z;x,y,z`）· 成员变量 `use_snap_points`/`locked`/`memo`/`tooltip` ＋ **`act` 现在可用 `player="Teal"` 把 Player 当作用对象**（`getHandCount`/`getHandTransform`/`getHoldingObjects`）。
  - 📌 **查了官方 API 才写的**（`api.tabletopsimulator.com`）：⚠️ **`Player.takeObject` 根本不存在** —— Player 只能 `getHandObjects(hand_index)`/`getHandTransform`/`getHoldingObjects`，所以"摸牌进手"的正路是**物件侧**的 `deal`/`dealToColorWithOffset`（我上一轮的设想是错的）。TTS = v14.2.2。
  - 测试从 **16 条扩到 25 条**（新增 9 条 hand 动作；`act` 的深层分支**离线抽不出来** ⇒ 只能源码级断言，真行为留给活体）。
  - ⚠️ 三个**新坑**（都当场抓到）：① 拼接脚本自己的 Lua 文本里有**反引号** ⇒ 把 JS 模板字符串提前闭合（改成数组 join）；② 单行锚点**不许假设行尾**（同一函数里两种行尾都有）；③ `hand` 的 if 链在 `take` 分支后就 `end` 了 ⇒ 新 `elseif` 插在**链内**才对（插到 `end` 之后 Lua 直接报语法错，已验证）。
- **2026-10-09 场 7**（**F8 定案：拼接进函数体内**）：
  - 🔍 **根因**：v14 那段原语被拼接进了 `setCount()` 中间 ⇒ 少一个 `end`、尾巴多一个 ⇒ **平衡 ⇒ 能编译、能注册、名字全 nil**。
    `hand` 活着是因为它在**拼接点之前**；那四个死在**之后**。台账里那条"矛盾证据"**根本不矛盾**（推论/证据 ⇒ `VALIDATION.md` F8）。
  - 🧰 **新工具 4 个**（`tts\tools\`，用法 ⇒ `MAINTENANCE.md` §1a）：`run_and_capture.js`（**抓子进程输出的唯一可靠姿势**）·
    `scan_exec.js`（逐行首语句报 `IN`/`NOT-IN`）· `check_block_depth.js`（每行块深度 ＋ 是否平衡）· `verify_f8.js`（每个行首定义的函数加载后是否真的存在）。
  - ⚠️ **两个假信号，各花掉一轮**（最值钱的一课）：
    ① `execFileSync` 在本沙箱**抛异常且 stdout/stderr 都是空** ⇒ 读起来就是"子进程什么都没打印"；
    ② 这些 Lua 文件是 **CRLF** ⇒ `split('\n')` 后每行**尾带 `\r`** ⇒ 行首判定全失配、**往行尾追加的标记永远不到达** ⇒
       看起来像"这一大片代码根本没执行"。⛔ **按行处理必须先 `.replace(/\r\n/g,"\n")`**。
  - 📌 **"门禁全绿"只证明它检查了的东西**：第 7 条门禁的抽取块**起点在拼接点下方** ⇒ 整段跳过死区 ⇒ 7 条全绿也看不见它。
    所以要单独问一句：**"这块 chunk 装得上、名字都在吗"** —— 现在 `test_bridge_primitives.ps1` 里加了第 2b 步
    （`verify_f8.js`：**每条行首定义的函数**加载后是否真的存在，判定看子进程写的 `VERDICT=` 状态文件）。
    **阴性对照已验**：装回"平衡但错位"的坏版本 ⇒ 门禁**立刻转红**（以前它是全绿的）。

## §10 关键数字（2026-10-09）

工作区文件 **3,395** · `tts\` 下 **37** 个 `.ps1` · 门禁 **7** 条（入口 `tts\tests\run_all.ps1`，要证据加 `-OutFile`）· 注入 **9.5 KB/请求**（发布 5.7 KB）。
