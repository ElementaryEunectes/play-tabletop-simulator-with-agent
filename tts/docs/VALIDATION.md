# VALIDATION.md —— 通用性验证台账（**"对任何 TTS mod 都成立"这句到底验到哪了**）

> **什么时候读我**：① 你要在文档/README 里写一句"通用"时；② 你要动 `play.ps1` / `dsh_global.lua` / `bootstrap.ps1` 时；
> ③ 有人问"这个工具链真能用在别的 mod 上吗"。
> ⛔ **本文件的规矩**：每行必须是**可复现的断言 ＋ 一行能重跑的证据**；**没测过的就写"未验"**，不许把"设计上通用"写成"已验证"。
> 📌 **两个来源**：① **真 mod**（实测，唯一算数的）；② `tts\tests\fixtures\` 的**假游戏 fixture**（只验"数据不在代码里"这条契约，**不算**通用性证据 ⇒ `BOOTSTRAP.md` §1b 已定案）。

## 0. 判据（一句话）

**换个 mod 还成立 ⇒ 通用；只对这一局成立 ⇒ 本局。**（`tts\docs\README.md` §开源的边界）

**状态词**：`✅ 已实测`（真 mod 上跑过，有命令与回执）· `⚠️ 部分`（跑过但只覆盖了一部分情形）· `❌ 不成立`（已知会失败）· `⛔ 未验`（**没人测过**）。

## 0b. 责任边界（2026-10-09 定案 —— 先读这段，否则下面全会被误读）

**我们交付的不是"能照着打任何一款的控制层"，而是**：

| | 谁负责 | 在哪 | 判据 |
|---|---|---|---|
| **通用原语层** | **本项目** | `tts\`（进仓库） | "换个 mod 还成立" |
| **某一款的控制层** | **用户**（照 `BOOTSTRAP.md` §2b 教出来） | `local\games\<游戏>\control\`（**不进仓库**） | 只对这一局成立 |

⇒ 所以下表的判据是**两层各问一遍**：① 原语够不够覆盖 TTS 的操作？② "教一款"能不能又快又便宜？
⇒ **`play.ps1` 不可通用不是缺陷**（F1 已按此重新定性）；真正的缺口是 **F6（原语覆盖）**。

---

## 1. 全链实测记录（两次真 mod）

| 轮次 | mod 形态 | 结果 |
|---|---|---|
| ① 2026-10-07 | **对局型**（座位 ＋ 计数板 ＋ 骰盘 ＋ 招式表） | 全链走通，包括 `play.ps1` 控制台 |
| ② 2026-10-09 | **非对局型**（无计数板/骰盘；自带 116 KB Global 脚本 ＋ 12 页笔记本） | **半过**：传话/存档/索引/认物/地图全过；**`play.ps1` FAIL**（见 §3 F1） |

> ⭐ **这一轮才是有价值的**：它把"通用"从"设计意图"变成了"**有反例的实测**"。一个反例 > 十次顺风验证。

## 2. 逐层台账

| # | 断言 | 证据（可重跑） | 状态 |
|---|---|---|---|
| L1 | 桥接能被烤进**任意**存档且**不弄坏 mod 自带的 Global 脚本** | `install_save2.ps1 -KeepLua -KeepTabs`；之后 `ping` 回 **`v13-turntoken`**（版本号 = 唯一凭据） | ✅ 已实测（②） |
| L2 | mod 自带的 116 KB Global 脚本 ＋ 12 页笔记本**原样保留** | 存档里笔记本页数与模组脚本 `function` 名逐条比对（②） | ✅ 已实测（②） |
| L3 | 纯 PowerShell 传话层不需要知道任何游戏 | `ds.ps1 -Do ping` ⇒ `ok v=v13-turntoken objs=115 loads=1` | ✅ 已实测（①②） |
| L4 | 存档侧全量索引不依赖游戏 | `obj_index.ps1 -File <存档绝对路径>` ⇒ 625 行 CSV（②）· 242 KB（①） | ✅ 已实测（①②） |
| L5 | 认物完全由**数据**驱动（`local\games\<游戏>\objects.json`） | `bootstrap.ps1 -Inventory` ⇒ 190 nicks / 41 hashes；换一款换一份 `objects.json` 即可 | ✅ 已实测（①②） |
| L6 | 地图输出随数据变（不是代码里写死的表） | `bootstrap.ps1` ⇒ ② **115 行**（7 区块）· ① **92 行**（8 区块） | ✅ 已实测（①②） |
| L7 | 卡库/别名/规则走 `cache\<game>_*.md/json`，路径由 `_current.md` 的 `GAME=` 决定 | `tts\config.ps1` §GAME 解析；`card.ps1 -Q` | ✅ 已实测（①）；② 未建卡库 |
| L8 | 隐藏区折叠规则**外置**，可跨游戏 | `diff_hidden.ps1 -Game <游戏>` ＋ `cache\hidden_zones.csv` | ⚠️ 部分（① 定过规则；② **未标过边界**） |
| L9 | 两层是**真的**分开的：`tts\play.ps1` 只是分发器，控制层住在 `local\games\<游戏>\control\` | ① 当前游戏无控制层 ⇒ 报 `NO PART this game has no control layer yet: ...`，**且不碰 TTS**；② 切到有控制层的那一款 ⇒ 入口加载它并**真的读到盘面**（当时回 `BAD DATA ... no object with guid cdd19a`＝控制层的数据过期，不是分层失败） | ✅ 已实测（2026-10-09 两向都试过） |
| L17 | **原语覆盖**：TTS 的往返操作我们够不够用 | 见 F6 的缺口表 | ⚠️ **约七成**（有余量靠 External Editor `exec` 兜底） |
| L10 | `roll.ps1` 读骰面 | `getValue` = 权威面（① 10 颗骰 · 6 轮实测） | ⚠️ 部分（② 的骰子在 `Infinite_Bag` 里动态生成 ⇒ **未验**） |
| L11 | 翻牌朝向 `rotZ` 0=上 / 180=下 | ① 在那张桌上标定 | ⛔ **未验**（是"通用原语"但**只在一张桌上标定过**，见 F2） |
| L12 | 哨兵/叫醒（玩家写字或回合推进能叫醒我） | `channel_watch.ps1` ⇒ `cache\chan.txt` ＋ file 哨兵 `^NEW \d` | ⚠️ 部分（机制通用；② 未重挂验证） |
| L13 | `front_watch.ps1`（前台横幅 → `TURN=Pn`） | ① 的 mod 自己画横幅才行 | ❌ **对没有横幅的 mod 永远出不了 `TURN=`**（`BOOTSTRAP.md` §1 D 已注明） |
| L14 | 脚本清单/文档指针不断链 | `tts\tests\run_all.ps1` 的 `doc references` 门禁 | ✅ 已实测（离线条） |
| L15 | 仓库里没有真游戏名（开源边界） | `tts\tests\test_agents_hygiene.ps1` 的游戏名硬线（**唯一例外** = `README.md`/`README.en.md` 的授权声明） | ✅ 已实测（离线条） |
| L16 | 换任何 mod 都能"一小时内打完一回合" | —— | ⛔ **未验**（`HANDOFF.md` §4 的目标判据；需要**第三方**在一台干净机器上试） |

## 3. 已知缺陷与空白（**别在别处复述，引用这里**）

**F1 · `play.ps1` 曾不是通用控制层 —— 已按 §0b 定性为"分层设计"**（`✅`，2026-10-09 修正）
它原先整份住在 `tts\`，读 `cache\<game>_rules.json` 且 `status` 也走 `$Rules.dice/seats` 那套"对局型" schema
⇒ 在第二款 mod 上连 TTS 都没碰就 `NO PART`。当时记为缺陷，**现在记为分层**：控制层本就只对一款成立。
**已做的隔离**：控制层移进 `local\games\<game>\control\`（`play`/`dice`/`rules`/`verbs`），仓库只留
`tts\play.ps1` 分发器 ＋ `tts\lib\bridge.ps1`（传输包装）。**建议**：新 mod 先用通用层，需要一个"一条命令一个阶段"
的控制台时再照 `BOOTSTRAP.md` §2b 教一个。

**F2 · "翻牌朝向"这个通用原语只在一张桌上标定过**（`⛔`）
`dsh_global.lua` 的 `draw` 用 `rotZ 0/180` 判面朝上/下，依据是 ① 那张桌上量到的 `~0.08` / `~180`。
**没在 ② 上验过**。⇒ 在别的 mod 上用 `draw` 前，**先取一张已知朝向的牌量 `rotZ`**，别假定。

**F3 · 离线门禁只跑假游戏 fixture**（`⚠️`，设计如此）
`test_game_data.ps1` 证的是"**数据不在代码里**"这条契约（用否定用例），**不是**"任何 mod 都成立"——后者只有真 mod 能证。
⇒ **每次来一款新 mod，都要照 `BOOTSTRAP.md` 走一遍并回写 §1/§2**。这是本文件存在的意义。

**F4 · `front_watch.ps1` 是"某一局专用"残留**（`❌`）
它靠读 ① 那款 mod 自己画的横幅色块判轮到谁。**换 mod 即失效**，但仍留在 `tts\`（因为 `read_turn.ps1` 引用它）。
⇒ 别把 `cache\front.txt` 当通用信号源。

**F5 · 桥接的 `exec`/`callx` 边界未验**（`⛔`，`BOOTSTRAP.md` §5 已列）
已知对"带脚本的物件"有效；无脚本物件 / 反复调用 / 并发 ⇒ **未验**。

**F6 · 原语覆盖缺口（按 §0b，这才是"通用层"的真待办）**（`⚠️ 约七成 → 首轮缺口已补`，2026-10-09）

`dsh_global.lua` 曾暴露 ~32 条命令 ＋ `act` 白名单 ~34 个动词，够跑通"读—认—摆—结算"的往返，但下面这些
TTS 有的操作**没有对等原语**（缺的都会被"教一款"直接踩到）：

| 原语 | 对应的人话 | 状态（2026-10-09） |
|---|---|---|
| `takeObject`（取**指定**那张，非顶张） | 「把**我点名**的那张牌拿到桌上」 | ✅ **已补** `cmd=take` ＋ `ds.ps1 -Do 'take:<deck>:<CardID>:<x>:<y>:<z>'` |
| `spawnObject` / `clone` | 「生成一个指示物 / 复制一份供给堆」 | ✅ **已补** `cmd=spawn`：`json` ／ `copyguid`（保留 mod 自己的图与 Lua）／ 纯 `type` |
| `destroyObject` | 「删掉 / 清理」 | ✅ **已补** `cmd=destroy` |
| `getPlayers` / 座位权威 | 「谁是谁、坐哪、什么颜色、**轮到谁**」 | ✅ **已补** `cmd=players`（＋ `cmd=player` 的 `turn`/`blind`） |
| 摸牌进手 / 整理手牌 | 「把牌给某人 / 摸 n 张进手」 | ✅ **已补**（v15）：`hand:<Color>:give:<guid>`（给某一张）· `hand:<Color>:draw:<容器guid>:<n>`（`Deck.deal`，非牌堆回落 `dealToColorWithOffset`）· `hand:<Color>:holding`（他此刻手上拿着的） |
| Zone / 容器遍历 | 「把这个袋子倒出来」 | ✅ **已补**（v15）：`cmd=container`（列出 Bag/Deck 内的物件 ＋ 数量 ＋ tags） |
| `setSnapPoints` / 吸附点 | 精确摆到 mod 定义的格位 | ✅ **已补**（v15）：`act:<g>:setSnapPoints`（`value=x,y,z;x,y,z`）＋ `act:<g>:use_snap_points`（成员变量） |
| `setTags` / `addTag` / `removeTag` / `hasTag` … | 「给物件打标签 / 按标签找」 | ✅ **已补**（v15）：`act:<g>:setTags:标签1+标签2`（⚠️ **TTS 的 tag 是哈希**，`getTags` 回哈希、`setTags` 要喂哈希 —— 从已带该标签的物件上抄） |
| 撤回 / 交易 | 杂项 | ⛔ **仍缺**（`cut`/`paste`/`drop` 已在 `act` 白名单里，但**未验证**；`copy`/交易无文档 API） |

⇒ 三条 🔴 硬前提（点名取牌 · 造物 · 座位权威）**已落地**，由 `tts\tests\test_bridge_primitives.ps1` 用
**真 Lua VM ＋ 从真文件抽取的代码**守着（**25 条用例**：16 条覆盖 v14 原语 ＋ 9 条覆盖 v15 的 hand 动作，
含"缺卡 / 幽灵容器 / 未知动作必须报错而非静默"）。
**兜底**：External Editor API（39999）能 `ExecuteLua` 任意代码 ⇒ 缺的原语"做不到"比"做得别扭"少，
但**它无回执、要状态前后对比验证**，不能当常规路径（`BOOTSTRAP.md` §2 B 第 3 条）。

**v15 补的是接口，不是"活体验过的功能"**：`setTags`/`setSnapPoints` 走的是 `act` 的深层分支
（⚠️ **无法离线单独抽取**，测试只能做源码级断言 ＋ 桩环境的 hand 动作），所以它们的**真实行为依赖下一轮活体验证**。

⚠️ **这些要生效必须先重烤存档**：桥接是**烤进存档**的，跑着的 TTS 里是旧版本。
实测（2026-10-09，旧桥在跑）：`container` 回 **`no handler for cmd=container`**；`hand:Teal:holding` 回
**`unknown hand action: holding`**（旧 `hand` 认识命令、不认识这个动作）—— 两条都说明**必须重烤**。
版本号是唯一凭据 —— 重烤后 `ping` 应回 **`v15-tags-snap-hand`**。

**F7 · 桥接原语的"活体"部分仍未验**（`⛔`，2026-10-09）
离线门禁用的是**文档形状的桩**，不是这台 TTS 的真实行为 ⇒ `spawn`/`take`/`destroy` 各需**重烤后真跑一次**
（尤其 `spawnObjectJSON` 的入参放宽：`{Name=..., Transform={posX=...}}` 与 `{type=..., position=N}` 两种都要试）。

**F8 · `players` / `take` / `spawn` / `destroy` 在活体上不可达，原因**未查明**（`❌`，2026-10-09）**
症状（活体实测原始回执）：
```
players -> handler error: Global:(5975,26-47): attempt to call a nil value
take    -> handler error: Global:(5970,23-44): attempt to call a nil value
destroy -> handler error: Global:(5972,26-47): attempt to call a nil value
```
列区间**正好等于**注册处那次调用（如 `DSH_players(m)`）的宽度 ⇒ 注册表里的那个名字在调用时是 nil。

**已排除的原因**（每条都做了实验，不是推理）：
- **不是"定义在表之后"**：定义在 5621、`handlers` 表在 5873、注册在 5975，顺序正确。
- **不是顶层 `return`**：全文没有列首的 `return`。
- **不是 200 局部量上限**：Lua 5.3 在 201 个时是**编译报错**（本机实测），而这份 chunk **能编译**（反汇编过，名字都在常量表里）。
- **不是形式问题**：`local x = function`、`local function x()`、全局 `DSH_x = function` **三种都试过**，结果一致。
- **不是重复桥接**：运行脚本里各标志行**只出现 1 次**。

**矛盾的核心证据**（用 `gen_bridge_alone_test.js` 在**运行中的字节**上复现）：
- chunk 内测得 `hand=function`（旧函数**能用**），而 `takeOne/players/spawn/destroy`（v14/v15 后加的）**全 nil**；
- **执行检查点**显示 chunk **执行到了 `handlers` 表之后**的代码，却**从未执行表之前**那些定义行（同一 chunk、顺序执行 —— 这互相矛盾）；
- 用 `error()` 做对分探测，在 `local function takeOne(m)`（1592 行，列首语句）处注入错误，**脚本仍能跑完并打出尾部输出** ⇒ 那里的"语句"似乎不在主 chunk 的执行路径上。

**下一步（唯一正确的做法）**：把运行脚本**二分**到"仍能观察到 `hand=function` 但 `takeOne=nil`"的最小片段，把它作为回归用例；工具已就位：`tts\tools\bisect_run.js`（在指定行注入 `error()`，报告是否到达）＋ `gen_bridge_alone_test.js`（从运行脚本或本地文件生成桩环境）。

⚠️ **在这些命令通过上面那条最小复现之前，一律按"活体不可用"对待** —— 离线门禁（含 26 条桩用例）**看不见这个问题**，这是本轮最值钱的一课。

**F9 · `dsh_global.lua` 的行尾从"故意混用"漂移成了单一风格**（`⚠️`，2026-10-09）
**先说结论：`.gitattributes` 的字节一致性承诺没问题** —— 用可靠方法验过：`git diff HEAD -- <file>` 为空，且
`git cat-file -s HEAD:<file>` = **96789 B** ＝ 工作区文件（`.NET` 直读）**96789 B** ⇒ 逐字节相同。
⚠️ 但我一开始用**不可靠的方法**（`git show ... > 文件` 经 PowerShell 重定向落盘）得到"HEAD 是全 LF、工作区是全 CRLF"，
据此写下了"承诺被打破"的结论 —— **那是方法造成的假象**。教训：核对二进制/编码相关的事实，**必须走 `git cat-file -s`
与 `[IO.File]::ReadAllBytes`**，别用 shell 重定向。

**真实且仍待处理的部分**：该文件现在是 **2045 行全 CRLF、0 行裸 LF**，而 `.gitattributes` 的注释写明本仓库
**故意混用**（原为 1607 CRLF ＋ 93 裸 LF）。本次会话的多次"文本模式编辑"（丢掉 `\r` 再统一补成 CRLF）逐步把它推成了单一风格。
⇒ 功能无影响（`validate_lua.js`、TTS 都过），但**与文件自身声明的意图不符**。要处理的话应一次性决定统一到哪一种，
并用 `[IO.File]::WriteAllBytes` 写入（不经任何文本模式编辑）。

## 4. 怎么续验（下一款 mod 来了照做）

1. 照 `tts\docs\BOOTSTRAP.md` §2 走"教一款新 mod"（存档 → 烤桥接 → `ping` → 索引 → `-Inventory` → `objects.json` → 地图）。
2. **照 §2 表逐行判**：`✅` 要写**命令 ＋ 回执**；失败就在 §3 记 `F<n>`（**记原始返回，别猜**）。
3. **专挑与上次不同的形态**（如：有骰盘的 vs 没有的 · 单人对面的 vs 多人的 · 有规则的 vs 纯沙盒）。
4. 回写本文件 §1 ＋ §2；**F1/F2 若被触发，就是新证据**，别当噪音。
