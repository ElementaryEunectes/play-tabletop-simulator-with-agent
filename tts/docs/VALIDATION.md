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
| L1 | 桥接能被烤进**任意**存档且**不弄坏 mod 自带的 Global 脚本** | `install_save2.ps1 -KeepLua -KeepTabs`；之后 `ping` 回 **`v16-tracker-guid`**（历次版本号都算通过：`v13-turntoken` → `v14-primitives` → `v15-tags-snap-hand` → `v16-tracker-guid`）（版本号 = 唯一凭据；v16 是 2026-10-11 03:44 玩家重载 `TS_Save_18.json` 后实测） | ✅ 已实测（②） |
| L2 | mod 自带的 116 KB Global 脚本 ＋ 12 页笔记本**原样保留** | 存档里笔记本页数与模组脚本 `function` 名逐条比对（②） | ✅ 已实测（②） |
| L3 | 纯 PowerShell 传话层不需要知道任何游戏 | `ds.ps1 -Do ping` ⇒ `ok v=v15-tags-snap-hand objs=115 loads=1` | ✅ 已实测（①②） |
| L4 | 存档侧全量索引不依赖游戏 | `obj_index.ps1 -File <存档绝对路径>` ⇒ 625 行 CSV（②）· 242 KB（①） | ✅ 已实测（①②） |
| L5 | 认物完全由**数据**驱动（`local\games\<游戏>\objects.json`） | `bootstrap.ps1 -Inventory` ⇒ 190 nicks / 41 hashes；换一款换一份 `objects.json` 即可 | ✅ 已实测（①②） |
| L6 | 地图输出随数据变（不是代码里写死的表） | `bootstrap.ps1` ⇒ ② **115 行**（7 区块）· ① **92 行**（8 区块） | ✅ 已实测（①②） |
| L7 | 卡库/别名/规则走 `cache\<game>_*.md/json`，路径由 `_current.md` 的 `GAME=` 决定 | `tts\config.ps1` §GAME 解析；`card.ps1 -Q` | ✅ 已实测（①）；② 未建卡库 |
| L8 | 隐藏区折叠规则**外置**，可跨游戏 | `diff_hidden.ps1 -Game <游戏>` ＋ `cache\hidden_zones.csv` | ⚠️ 部分（① 定过规则；② **未标过边界**） |
| L9 | 两层是**真的**分开的：`tts\play.ps1` 只是分发器，控制层住在 `local\games\<游戏>\control\` | ① 当前游戏无控制层 ⇒ 报 `NO PART this game has no control layer yet: ...`，**且不碰 TTS**；② 切到有控制层的那一款 ⇒ 入口加载它并**真的读到盘面**（当时回 `BAD DATA ... no object with guid cdd19a`＝控制层的数据过期，不是分层失败） | ✅ 已实测（2026-10-09 两向都试过） |
| L17 | **原语覆盖**：TTS 的往返操作我们够不够用 | 见 F6 的缺口表 | ⚠️ **约七成**（有余量靠 External Editor `exec` 兜底） |
| L18 | `turn_tracker` 认**调用方给的 guid**（读的那件 = 校准档写的那件，不再只看烤进去的常量） | 正向做法：信封**在进程内构造**（⛔ 绝不跨 `-File`，⇒ F14），给一枚**真实存在但不是 tracker** 的件 ⇒ 应答里 `guid` 是**它的**、**位置也是它的** | ✅ **已实测（2026-10-11 14:11）**：`guid=145cd9`（Brown 手牌计数板）⇒ 回复 `ok / guid=145cd9 / side=player / x=12.00 / z=-15.00` —— **`x=12` 是判据**（tracker 常在 `x≈0`，校准档两个落点 `x=0` / `x=0.05`）⇒ **调用方的 guid 真被采纳**；且**这条命令之后窗口仍在 LISTENING** ⇒ 与"根因是畸形信封"互为印证 |
| L19 | **39998 的单槽争用有根治**：一个常驻 hub 独占回复端口，其它工具把信封投给它 | 起 `tools\tts_hub.ps1` 后跑 `tests\live_smoke.ps1`（**17 条连发**）⇒ 应全过且 **TTS 的 API 不掉**；同时跑轮询器**不再** `listener busy` | ✅ **已实测（2026-10-11 13:59，干净窗口＝无轮询器）**：hub **连续服务 22 条**（含 `live_smoke` 的 **17 条连发** ＋ 交还那一条 messageID 3），**28–79 ms**，**零 `listener busy`**；**连发之后 `39999` 仍在 LISTENING**，再 `ping` 也正常 ⇒ 正是过去会打死 API 的那个形状，现在过了 |
| L10 | `roll.ps1` 读骰面 | `getValue` = 权威面（① 10 颗骰 · 6 轮实测） | ⚠️ 部分（② 的骰子在 `Infinite_Bag` 里动态生成 ⇒ **未验**） |
| L11 | 翻牌朝向 `rotZ` 0=上 / 180=下 | ① 在那张桌上标定 | ⛔ **未验**（是"通用原语"但**只在一张桌上标定过**，见 F2） |
| L12 | 哨兵/叫醒（玩家写字或回合推进能叫醒我） | `channel_watch.ps1` ⇒ `cache\chan.txt` ＋ file 哨兵 `^NEW \d` | ⚠️ 部分（机制通用；② 未重挂验证） |
| L13 | `front_watch.ps1`（前台横幅 → `TURN=Pn`）—— **2026-10-11 已归档**（`~\.dsh\archive\tts-legacy\`，见 F4） | ① 的 mod 自己画横幅才行 | ❌ **对没有横幅的 mod 永远出不了 `TURN=`**（`BOOTSTRAP.md` §1 的唤醒机制已注明） |
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

**F4 · `front_watch.ps1` 是"某一局专用"残留**（`❌` → **2026-10-11 已归档**）
它靠读 ① 那款 mod 自己画的横幅色块判轮到谁。**换 mod 即失效**。
✅ **处置（2026-10-11，用户拍的）**：它和 `read_turn.ps1` **都移出了仓库** ⇒ `~\.dsh\archive\tts-legacy\`（字节一致，SHA256 对拍过）；
`cache\front.txt` 从此**没有生产者**，别再把它当信号源。
⚠️ **2026-10-11 追加（读文档时别被"休眠保留"骗）**：`read_turn.ps1` 的**本体仍是那次批量替换的残骸** ——
`$hotsDir`（原 `$ShotsDir`）· `$ilentlyContinue` · `$img.$Dispose()` · `$ist` · 参数 `$S` 被当成 y 坐标……
**`check_ps1.ps1` 报 0 错**（这些都是**合法的** PowerShell：未定义变量不是语法错），但一跑就错。
而 `front_watch.ps1` 每轮都会调它 ⇒ **这条链即使被重新启用也跑不起来**。
⛔ **没有修**（链已停用）：要复用就得逐行还原（原始意图可从 `git show 3fbbde9:tts/read_turn.ps1` 与同事故后修好的
`index_images.ps1`/`tts_api.ps1` 头部描述推断），或者把两个文件一起移出仓库（"死脚本别留 `tts\`"）。

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
**真 Lua VM ＋ 从真文件抽取的代码**守着（**31 → 30 条用例**（`test_bridge_primitives.ps1` 自报 `30 passed, 0 failed`；2026-10-11 复测）：覆盖 v14 原语 ＋ v15 的 hand 动作 ＋ `spawn` 三种入参形态，
含"缺卡 / 幽灵容器 / 未知动作必须报错而非静默"），**外加第 2b 步**：整块桥接加载后**每条定义是否可达**
（F8 ⇒ 见下；这条是 2026-10-09 补的，因为抽取块**跳过了**坏区）。
**兜底**：External Editor API（39999）能 `ExecuteLua` 任意代码 ⇒ 缺的原语"做不到"比"做得别扭"少，
但**它无回执、要状态前后对比验证**，不能当常规路径（`BOOTSTRAP.md` §2 B 第 3 条）。

**v15 补的是接口，不是"活体验过的功能"**：`setTags`/`setSnapPoints` 走的是 `act` 的深层分支
（⚠️ **无法离线单独抽取**，测试只能做源码级断言 ＋ 桩环境的 hand 动作），所以它们的**真实行为依赖下一轮活体验证**。

⚠️ **这些要生效必须先重烤存档**：桥接是**烤进存档**的，跑着的 TTS 里是旧版本。
实测（2026-10-09，旧桥在跑）：`container` 回 **`no handler for cmd=container`**；`hand:Teal:holding` 回
**`unknown hand action: holding`**（旧 `hand` 认识命令、不认识这个动作）—— 两条都说明**必须重烤**。
版本号是唯一凭据 —— 重烤后 `ping` 应回 **`v15-tags-snap-hand`**。

**F12 · 跨 mod 驱动：`Object.call` 会弄死 TTS，官方 `messageID 3` 安全但看不见物件私有状态 —— ✅ 已定案（2026-10-11）**
**目标**：让"交出回合"不用玩家动手（代按那枚 Turn Tracker 的 End Turn）。

| 尝试 | 实测结果 | 结论 |
|---|---|---|
| 桥接 `callx`（= `Object.call`）调 `forwardOneTurn()` | **两次**都是 25 s 无回执 ⇒ 立刻 `TTS unreachable`、端口不再 LISTEN | ⛔ **判死**（`spawnObject`、写 `script_state` 也在这条机制的嫌疑名单上） |
| 官方 **External Editor API `messageID 3`**（`{messageID:3,guid,script}`）执行同一函数 | **TTS 健康**，且把 mod 自己的 Lua 错误回执给我 | ✅ **安全通道**；新工具 `tts\tools\exec_script.ps1` |
| 在 `messageID 3` 里读该物件状态 | `currentColor=nil`、`o.script_state='[]'`、`o.getVar=nil`、**`pairs(o)` 空**、`o.getName()=''`（而 `getDescription()` 正常 269 字） | ⛔ **物件私有状态对这条通道不可见** |
| 重新定义它的 `moveTurn`/`placeToken`/`findNextPlayerColor` | 注入成功、TTS 健康，但**读不到状态 ⇒ 算不出下一个颜色**（`currentColor` 恒 nil） | ⛔ 补丁无法在外部环境自洽 |
| 注入 `onExternalMessage` 让它**在物件环境**里执行 | 处理器注入成功，但 `{"cmd":"dshPing"}` 回的是**桥接**的 `no handler` ⇒ **自定义消息只送给 Global 脚本**，不触发物件的 `onExternalMessage` | ⛔ 没有"从外部触发物件回调"的口 |
| `messageID 3` 的**返回值** | 官方文档说走 messageID 5，但**从未到达**本机监听器；只有 `print()`（messageID 2）与错误（messageID 3）回得来 | ⚠️ 验证只能靠**副作用 ＋ print** |

**结论**：**跨 mod 的外部驱动做不到**（它的状态私有、且无对外触发口）。**交还回合由玩家按** —— 只要玩家自己按得动（待玩家实测确认），这是**唯一受支持**的路径。
📌 **这句已被本节末尾的「后续定案（2026-10-11 02:2x）」部分取代**：agent **可以**用 `tts\tr.ps1` **搬位置**交还回合，玩家只负责**按按钮前进** —— **位置是唯一判据**，颜色可能错位（⇒ 见下）。
**两个可复用的坑**：① **脚本必须"直连 TCP 从文件发"** —— 经 `-Lua` 参数传会被吃掉**引号**（`print("A")` 到达时变成 `print(A)` ⇒ 打印 nil）；② **多行脚本经命令行会被改坏**（`unexpected symbol near '='`）。
**排查时机**：`Player.log` 的**最后写入时间**比进程列表可靠（本机 `Get-Process`/`Get-CimInstance` **看不到** TTS，尽管它在跑；`netstat` 看 `CLOSE_WAIT`/`LISTENING` 才准）。
⛔ **`callx` 从未被修复，也别再试**（2026-10-11 查证＋澄清）：它的实现至今仍是 `o.call(fn, args)`，`git log -S 'callx'` 显示它只在"基线"与"加入它那次"提交里出现过，**之后再无改动**；今晚所有改 `dsh_global.lua` 的提交都是**删除实验**，没有一条修它。
📌 当时我在对话里说过"`messageID 3` 这条路修好了" —— 那指的是**新写的 `tts\tools\exec_script.ps1`（走官方 External Editor API 的 messageID 3）**，**不是** `callx`。两者**互不相干**：`exec_script.ps1` 可用（只读诊断），`callx` 碰了就挂。

**F13 · 桌上那枚社区 Turn Tracker 的"按钮没反应" —— ✅ 根因是它的 `Name` 字段为空（2026-10-11）**
**现象**：玩家按它的 `End Turn` 没反应（棋子不动）、也拖不动（`LOCKED=true`）；控制台**没有新红字**。
**⛔ 我先前的错误结论（已推翻）**：我写成了"它用 `Player[color].getPlayerHand()`，而本机已删掉这个方法 ⇒ 按钮对玩家也坏"。
**实测反驳**：在同一环境里探测 `Player[getSeatedPlayers()[1]].getPlayerHand` 得到 **`function`**（**存在**）。
**真正根因（同刻读数）**：`o.getName()=''` ＋ `script_state='[""]'` ⇒ 它内部 `currentColor` 是**空字符串**：
```lua
findNextPlayerColor: playerList = explode(self.getName())   -- 名字空 ⇒ 列表无效
                     ⇒ playerList = getSeatedPlayers()      -- 回退分支
                     ⇒ 找 color == currentColor("") 找不到 ⇒ 打印 "color was not found"、返回 nil
moveTurn: currentColor = nil ⇒ placeToken() 里 Player[nil] ⇒ 报 "cannot access field  of userdata<^LuaGlobalPlayer>"
```
**修法（它自己文档写明，无需改脚本）**：把**颜色顺序填进它的 `Name` 字段**（描述原文："enter the colors, capitalized and separated by spaces"）＋ **让玩家按一次**让它初始化 `currentColor`。
实测：`setName("Brown Teal")` ＋ 玩家按一次 ⇒ `currentColor='Brown'`、`script_state='["Brown"]'`、**按钮恢复移动**。
📌 **副作用教训**：我为了"外部代按"曾用 `messageID 3` **在它的运行环境里重定义** `placeToken`/`findNextPlayerColor`/`moveTurn` —— 那会**污染它的正常行为**（它随后打印 `placeToken: no known position for color=Red/...`）。清理办法 = 把**存档里的原始函数源文**重新执行一遍（`tts\tools\exec_script.ps1` ＋ 从 `LuaScript` 抽出的原文）⇒ 已复原（`RESTORED originals`）。

📌 **后续定案（2026-10-11 02:2x）—— 两处更正，一次说清**：
1. **它的位置功能是好的**：玩家按一下 ⇒ `currentColor` 前进一步 **＋ 棋子挪到那个人的手牌位置**（实测：`Brown→Teal` 时 `z −15 → +15`，且 `SAVED_STATE` 与 `LIVE_COLOR` **同时**变 Teal）。
2. ⛔ **外部写 `o.script_state` 只改"存档值"，改不了运行时 `currentColor`** —— 实测：写完回执 `state=["Brown"]`，同刻读 **`LIVE_COLOR='Teal'`**（没变）。而**它的按钮读的是运行时那个**。
   ⇒ **推论（解释玩家看到的一切）**：**错位**时（位置在一侧、运行时颜色却在另一侧），玩家按一下会把棋子挪到**它以为那个人的手牌位置** —— 常常**正好与原位重合** ⇒ 看起来"按钮没用"，其实颜色已推进。
   ⇒ **正解**：**位置是唯一判据**（`tts\tools\turn_side.ps1` 读它）⇒ **交回只搬位置**；**颜色交给按钮自己按**（按到对齐后即恢复正常来回）。`tts\tr.ps1` 仍写 `script_state`（让存档与棋子一致），但**不再声称它改变运行中的回合**。
3. ⚠️ **`Name` 必须写颜色顺序**（本机 `Brown Teal`）：空名字会让它按 10 色表轮转 ⇒ **跑到 `Red` 这类空座位**（玩家最早报告的现象，正是这条）。
🔧 **体检工具**：`tts\tools\tracker_read.lua`（配 `exec_script.ps1`）一次读出 `POS / SAVED_STATE / LIVE_COLOR / LOCKED / NAME` —— **`POS` 与 `LIVE_COLOR` 同侧才算对齐**。
🧠 **同一类错我这一小时犯了三次**（"`getPlayerHand` 已删"、"写状态不生效"、"它的位置功能坏了"），**每次都被一次同刻读数推翻** ⇒ 规矩：**改别人物件的状态不能只改一半；谈"前后"必须用同一时刻的读数**。

**F14 · TTS 的 editor API（39999）"窗口"会消失 —— `⛔ 根因未定`（2026-10-11，共 7 次）**

> 🎯 **14:0x 定案：根因是"畸形信封"，不是 guid／v16／连发／`-Raw`**（我自己的操作错误）：那条 `ds.ps1 -Json '{…}'` 是**经 `powershell -File` 传的**，而坑就在 `ttslib.ps1` 的注释里 —— **`-File` 会吃掉内层双引号**（`'{"cmd":"ping"}'` 到达时成了 `{cmd:ping}`）⇒ 送进 TTS 的是**畸形 JSON** ⇒ 命令收下、永不回复（`no reply in 25s`），随后 `39999` 不再 LISTENING。
> **对全部数据的检验**：**7 次掉线全部紧跟一次这种"经 `-File` 传 JSON"的调用**；`-Do`（无引号单 token）、桥接、以及**进程内构造**信封的调用（含 22 条连发）**一次都没事** ⇒ `-Raw` 只是**恰好同时出现**，被冤枉了。
> ⛔ **纪律（最终版）**：**永远不要把 JSON 交给 `powershell -File` 的参数** —— 用 `-Do` 那种无引号单 token、或**同进程内构造**（`@{…} | ConvertTo-Json`）再交给 `Invoke-Tts`、或把完整信封**写进文件**再读。`Repair-BareJson` 只救得了"裸词"那一种形态。
> ✅ **hub 至此完全洗清**：它只照实转发（畸形串也照转），所有正常调用经过它都安然无恙（22 条连发、28–79 ms、零 `listener busy`）。

> ⭐ **对照实验（13:45，用户拍板做的，设计 = 被动基线 ＋ 对照 ＋ 处理）**：
> 1. **被动 120 s、零命令** ⇒ 端口**全程 OPEN**（只 1 条状态记录）⇒ **它不会因为闲置而掉**。
> 2. 随后**经 hub** 连做 **2 条对照**（`turn_tracker` ＋ **正确的 tracker guid `0e731f`** —— 与轮询器一直在发的**同一条**）＋ 1 条处理（换成手牌计数板的 guid）：**第一条对照就掉**（`no reply in 25s` ⇒ 端口 closed；后两条自然 `ERR TTS unreachable`）。
>    ⇒ **guid 无罪**（真/假、tracker/非 tracker 都一样）；**v16 新增的 `m.guid` 路也无罪**；"连发"同样不是必要条件（这次是**本条窗口里的第一条命令**）。
> 3. 再**被动 180 s、零命令** ⇒ 端口**一直 closed**（这次 >3 min 没自己回来，而 13:40 那次掉线后 ~2.5 min 就回来了）⇒ **也不按固定节拍回来**。
> 🔎 **唯一还站得住的线索（n=6，还不是结论）**：**6 次掉线全都紧跟一次 `ds.ps1 -Json … -Raw`**；同一窗口里的 `-Do` 形式与桥接调用（含轮询器 4 条、`tr.ps1` 那条 messageID 3）**一直是好的**。
> ⚠️ **13:51 又一条强线索（未定）：轮询器会把窗口"烧掉"** —— 那次窗口由 port 哨兵看到 OPEN，**一条 ping 过去就已经 closed**；而 `cache\hub.log` 显示同一时段**每 ~2 s 一对** `turn_tracker` ＋ `index`（= 某个轮询器在探头，`index` 是 `turn_side.ps1` 的回落路径）。
> ⚠️ **13:59 反证（两条线索都被削弱）**：在**没有轮询器**的干净窗口里，hub **连续送 22 条**（含 `live_smoke` 17 条连发 ＋ 一条 messageID 3）**28–79 ms**，**窗口之后依然 OPEN**、再 ping 正常 ⇒ **"用过就很快关" 和 "轮询器烧窗口" 都不足以解释**；现在数据只支持一条更窄的说法：
> **危险的是"每条命令各自去绑/解 39998"的旧客户端路径**（六次掉线都在它上面；hub 独占该端口之后 22 条连发安然无事）。
> ⇒ **处置**：⛔ **先别用 `ds.ps1 -Json -Raw` 发命令**（改用 `-Do …` 形式或桥接），直到有人查清它与 `-Do` 在线上到底差在哪；**API 会随时消失 ⇒ 每个工具都要能容忍"这一条没了、下一条窗口再发"**（轮询器本来就容忍：它只在读到 `mine/player` 时才写文件）。

**时间线（都是实测）**：`03:44:34` `ping` 成功 ⇒ **`ok v=v16-tracker-guid objs=118 loads=1`**（玩家刚重载 `TS_Save_18.json`，新桥接确实生效）；
随后我发了一个**缺 `customMessage` 的信封**（`ds.ps1 -Json '{"cmd":"turn_tracker","guid":"deadbeef"}'`，本意是验"桥接认调用方的 guid"）⇒ 无回执，`ERR no reply in 25s`；
`03:45:05` 起 `Player.log` **不再增长**，`39999` **不再 LISTENING**（`netstat` 只剩 TIME_WAIT/CLOSE_WAIT），`ds.ps1 -Do ping` 变 **`ERR TTS unreachable`**。
**`Player.log` 尾部**：一长串 `Curl error 56: Recv failure: Connection was reset` ＋ 一次 Unity 资源卸载（`Unloaded 38 unused Assets`）。
**两个候选，都没证**：① 我那个**坏信封**（缺 `messageID`/`customMessage`）；② TTS 自己在**大量素材下载被重置**之后卡住/退出。
📌 **同刻的第二个会话独立观察到同一件事**（提交 `d04f452`，03:45:51）：它那次**交接失败在 `listener busy on 39998`**（不是 39999），随后也发现"**TTS 已关闭**（39999 无监听）"，
并据此**停掉轮询器、取消它那个 file 哨兵、删掉还在写 `mine` 的 `cache\turn_side.txt`**。
⚠️ **03:49 补正（别把结论写重了）**：`Player.log` **仍在增长**（最后写入 `03:48:05`，尾部只有两次 Unity 资源卸载、**没有崩溃/退出痕迹**）⇒ 准确说法是
**「TTS 进程活着，但 39999 这个 API 端口关了」**，不是"进程崩了"。最可能：**存档被卸载/退回菜单**，或那次重载之后 API 没重开。
⇒ 修法：**在 TTS 里确认 External Editor 开着**，或**重启 TTS 并重新载入存档**；回来先 `ds.ps1 -Do ping`。
📌 **那次哨兵触发是延迟投递**：它描述的是 `03:44:29` 的 `player→mine` 边沿（第 1/500 次），收到时 `cache\turn_side.txt` **已被另一会话删掉** ⇒ **没有可交还的回合**，也不重挂（链路要等 TTS 回来重建）。
🔁 **API 会"掉线"，四次都发生在"一次调用里连发好几条命令"之后**（2026-10-11：`03:44` / `03:51` / `03:53` / `13:28`）。**已推翻的两个解释**（都写下来，别重走）：
- ⛔ ~~"不存在的 guid 是元凶"~~ —— **被我自己推翻**：`13:28` 改用**真实存在但不同**的件（Hand Cards counter，guid ⇒ 该局 `STATE.md`）发同样的 `turn_tracker`，**照样掉线** ⇒ guid 真不真**无关**。
- ⛔ ~~"该 mod 素材下载被重置（`Curl error 56`）"~~ —— 那是**另一件事**，时间线也对不上。
✅ **目前的解释（与全部四次一致）：问题在"连发"**。四次都是**在 1–2 秒内连着发 3–5 条命令**，掉线总在**最后一条**；`netstat` 每次都留下 **CLOSE_WAIT / FIN_WAIT_2**（半开连接）。
**39998 只有一个槽**：我们每条命令都要绑它、TTS 再连回来送回复；连发 = 一轮接一轮地绑定/半关，TTS 那侧的回复通道跟不上 ⇒ 表现为 **`no reply in 25s`**（命令收下了、回包送不到），随后 **39999 不再 LISTENING**。
**反证**：轮询器每 **2.5 s 一条**、整夜长跑，**从未**掉线。
⛔ **纪律（修正版）**：**别把多条命令塞进同一次调用** —— 一条一条、中间留几秒；一条失败/超时后**先看端口**，别立刻补一条（那正是把 API 推下去的动作）。
✅ ~~**L18 的正向验证现在可以安全做了**（既然 guid 无罪）~~ —— **这句话被 13:40 的实测推翻**：**经 hub、单独一条**、给的是**真实但不同**的 guid，API **照样掉**（第 5 次）⇒ **guid 嫌疑回来了，而且这次没有"连发"可以背锅**。
⇒ 处理办法：**port 哨兵盯 `39999`**（开了才动手）；再哑就**重启 TTS 并重载存档**。✅ **hub 已落地并部分验证**：常驻 **`tts\tools\tts_hub.ps1`** 独占 39998，`ttslib.ps1` 优先走它（没有 hub 才回落自绑）—— 13:40 在岗期间连续服务 8 条、28–101 ms、**零 `listener busy`**（⇒ L19）。
⚠️ **它同时定案了快链引入的一个真缺陷**：**39998 只有一个槽**，而轮询器每 2.5 s 探一次 ⇒ 它每一轮都占这个槽一小片，
于是**交接**（`tr.ps1`/`exec_script.ps1`）会撞 `listener busy`；缓解 = 把绑定重试从 3 次提到 **6 次/~10 s**（已提交），
**真正的修法**是"**一个常驻进程独占 39998、其它人走它**"（⇒ `PRIOR_ART.md` 的 hub 方案），不是继续加 retry。
（沙箱里 `Get-Process`/`tasklist` **看不到** TTS，也看不到占端口的 PID ⇒ 只能靠 `netstat` ＋ `Player.log` 的 mtime 判断，这两条都用上了。）
**纪律（照 F10 的老教训）**：⛔ **`ds.ps1 -Json` 只发完整信封**（`{"messageID":2,"customMessage":{…}}`）；⛔ **一条一条探，别连着发**。
**还没做**：TTS 回来后 ① 验版本号是否仍为 `v16`；② 用完整信封补做 `turn_tracker` 的 guid 验证（⇒ L18）；③ 重挂轮询器与 file 哨兵。

**F7 · 桥接原语的"活体"部分**（`🟡` 部分完成，2026-10-09）
离线门禁用的是**文档形状的桩**，不是这台 TTS 的真实行为 ⇒ 每条都得**重烤后真跑一次**。
**已跑（载入 `TS_Save_11.json` 后逐条真跑）**：`ping` 版本对 · `players` 回 `ok count=2` ＋ 每座位一行 ·
`take` 缺卡回 `no container with guid ...` · `destroy` 幽灵回 `no object with guid ...` ·
**`spawn:copy` 回 `ok mode=copy guid=...`（objs +1）**。
⇒ **`spawn:copy` 覆盖"造物"这个硬前提的主用途**（复制桌上现成棋子，连卡面/Lua/状态一起）。
⛔ **`spawn:type`（通用造物）已在代码里显式拒绝**（`spawnObject` 造自定义件必弹模态窗）⇒ 见下 **F10**；
`spawn:json`（走 `spawnObjectJSON`）**未单独活体验**，但离线用例覆盖。
⚠️ 本次 `spawn` 的**第一次探测把 TTS 打挂了**（探测前 `ping` 正常，之后 API 不可达、进程仍占着 `Player.log`）⇒ **以后一条一条探**。
⚠️ **两个缺陷就是这次活体抓出来的**（离线门禁看不见，因为没有任何用例走 `type` 这条路、桩也从不回 nil）：
1. **`spawn:type` 把 Lua 表塞给了 `spawnObjectJSON`**。文档（`api.tabletopsimulator.com/base`）写得很清楚：
   `spawnObject({ type = ..., position = ... })` 收**表**，`spawnObjectJSON(jsonString)` 收 **JSON 字符串**（承载完整对象数据）。
   表给后者 ⇒ 回 nil，而报错却写成"needs TTS v13.2+" ⇒ **把 API 用错说成了版本不够**。
   ⇒ 现在 `type` 走 `spawnObject`，`json` 走 `spawnObjectJSON`。
2. **`S(v)` 对 nil 返回 nil** ⇒ 所有 `"..." .. S(x)` 在**正好要报错的那种值**上当场崩。活体原话：
   `spawn -> handler error: Global:(5704,8-122): attempt to concatenate a nil value`。
   ⇒ **报错路径自己死了，比没有报错路径更糟**（错误信息完全丢失）。现在 `S()` **永远返回字符串**（67 处调用，没有一处依赖 nil）。
⇒ 离线补了 `spawn` 各形态的用例；**阴性对照已验**：把表塞回 `spawnObjectJSON` ⇒ `spawn by type` 立刻红。

**F10 · `spawn:type` 在活体上会卡死桥接线程并被 TTS 回滚 —— `⛔ 未解`，2026-10-09 决定停止追查**
**现象**：`{cmd="spawn", type="Block", x=3,y=2,z=3}` ⇒ 调用方 `ERR no reply in 25s (skipped 1 broadcasts)`；
事后 `objects` **不变**、`spawn_last`/`spawn_trace` 的后续埋点**永不写入**；桥接本身**仍然健康**（紧接着 `ping`/`players`/`diag` 都正常）。
**证据（活体埋点，一次读清）**：处理函数**入口**写了 `__spawn_trace = "enter ... type=Block"`，
而**紧跟在 `spawnObject(...)` 之后**的那句埋点**从未出现** ⇒ **卡的是这次调用本身**，
不是"回执被吞"（没有回执可吞：处理没执行完）。TTS 随后把这次脚本改动**回滚** ⇒ **连"物件造出来了"都不能算**
（早期曾观察到 `objs 115→116`，那是回滚**之前**的瞬时读数）。
**三次尝试（都不成立，留证以免重走）**：
1. **不再触碰新造物件**（去掉 `getLuaScript`/`call("onLoad")`／`type` 路径不再 `placeFace`）⇒ 仍静默；
2. **改用 `callback_function`**（不等返回值，官方文档给的取对象方式）⇒ **仍静默**，说明卡的是**调用**而非"等返回值"；
3. **拆成两条消息**（请求只入队并立刻回执，下一条消息才造物）⇒ **未验证即停止，代码已删除**（`spawn_step` 不再存在）。
**为什么不值得再追**：`spawnObject` 只造 **TTS 内置件**，造不出 mod 的原件（那些是 Custom 对象，走 `clone`／`spawnObjectJSON`）；
本局真正需要的是"复制桌上现成棋子" ⇒ 由 **`spawn:copy` 覆盖**（已活体验过）。⇒ 记录在此，等真的需要通用造物时再捡起来。
🔎 **诊断面已清除**：`spawn_trace` / `spawn_last` 埋点与 `spawn_step` 命令随本次彻查一并删除（`spawn:type` 现在**显式拒绝**并指向 `copyguid`）。

**F11 · "可点的回合标记"这条需求本身选错了载体 —— ✅ 已换载体（2026-10-10）**
**最初的目标**（`HANDOFF §7.9`）：让**玩家点一下**即被观测到 ⇒ 做一个**可点令牌**，点一下把回合号写进**昵称**，`diff_index` 顺便差 `nick`。
**结果**：为了把这个物件做出来，先后撞上**四堵墙**（每一堵都实测过、都有回执）：

| # | 实测事实 | 证据 |
|---|---|---|
| 1 | **`spawnObject` 造自定义件必弹「自定义板块」模态窗**（带/不带贴图参数都一样），窗口挂着 ⇒ 线程被挂、回执永不到、脚本改动随后被回滚 | 两次玩家截图 ＋ `spawn_trace` 停在入口埋点 |
| 2 | **烤进存档的自定义件会被 TTS 在载入时丢弃** | 四个不同 `guid`（`ff73d9`/`b05e29`/`385a35`/`7e0793`）在活体里**全部查无此物**；文件里明明有 |
| 3 | **`clone` 能造、能留、脚本会初始化**，但它**继承源对象的 `script_state`** | `token_plain` 造的令牌带着模组计数板的 `{"color":"Brown"}` |
| 4 | **可点入口是 `createButton`（XMLUI），不是物件 `onClick`**；且按钮要按物件朝向摆放 | 模组 5 个物件脚本里 `onClick` 出现 **0** 次；按钮曾倒贴在底面（玩家截图） |

**换的载体（最终）**：**桌上玩家自己按的那个 Turn Tracker**（社区件，`Locked=true`、**在存档里**）+ **每款 mod 一次校准**
（`tts\tools\turn_calib.ps1` → `cache\<game>_turn.json` → 运行时 `tts\tools\turn_side.ps1`，哨兵盯它翻转）。
⇒ **§7.9 的判据 = "Tracker 从你那一侧移到我的侧"**（`player -> mine`），**玩家按一次即可，不需要打字**。

⛔ **本轮做的那些实验全部删除**（2026-10-10 彻查）：`turn_token` · `token_plain` · `spawn_step` · `turn_end` · `turn_get` ·
`turn_state` · 桥接里的 `DSH_TURN_N`/`DSH_STATE` 记账变量 · `__spawn_trace`/`__spawn_last` 埋点。
⚠️ **2026-10-11 发现：代码删了，件还在** —— 桌上仍有一枚我们造的 `DSH-TURN`（`guid a7bf2e`，`Custom_Token`，脚本 **2,053 B**，`state {"n":0}`；
脚本头写着"给没有回合标记的 mod 用的可点令牌"，带 XMLUI 按钮，点一下翻面并 `broadcastToAll("[DSH] turn N ended")`）。
**没人引用它**（校准档 `cache\<game>_turn.json` 与桥接常量都是 `0e731f`）⇒ **玩家可以把它删掉**。
看出它的工具：`tts\tools\dump_lua.ps1 -List`（列出存档里每个带 `LuaScript` 的件）。

两条理由：① 它们要么被 TTS 撤销、要么要靠重载才生效；② **回合流水本就该记在 `STATE.md`**（那一局状态的唯一真源）——
另开计数器就是第 4 条禁止的"同一事实两处"。**留着的只有**：Tracker 校准 ＋ `turn_side.ps1`（实时信号）＋ `turn_tracker` 命令（读那件的位置）。

**两条 API 级硬事实**（都是官方文档写明的，我先前却在猜 —— 已写进平台宪章第 4 条）：

- `Object.name` 是**内部资源名**（`Custom_Token`），**显示名要用 `getName()`** —— 文档原话 "generally, you want getName()"；
- **`getNickname()` 根本不存在**（本机实测报 `cannot access field getNickname of userdata<LuaObject>`）—— 昵称是**成员变量** `nickname`。

**教训**（已写进平台宪章第 5 条）：**同一个东西修到第三次仍要绕 ⇒ 退回需求层换载体**；**通用能力别绑在易碎的一次性载体上**；**把"换掉载体"作为选项摆给人选**。

**F8 · `players` / `take` / `spawn` / `destroy` 在活体上不可达 —— ✅ 已定案并修复（2026-10-09）**
**根因一句话**：v14 那段原语**被拼接进了 `setCount()` 的中间** —— 插在它最后一条语句 `out.state = ...`
和它自己的 `return out` / `end` **之间**。于是 `setCount` 的结尾被甩到 `DSH_destroy` 之后，而**从新块开始的
一切**（`placeFace` · `takeOne` · `players` · `spawn` · `destroy` · 连同后面整张 `handlers` 表）**都变成了
`setCount` 的函数体** ⇒ 加载时**从不执行**。补上 `setCount` 的收尾、删掉错位的那两行即可。

- **为什么表现成"名字是 nil"**：chunk 照样**编译通过**（少一个 `end`、尾巴又多一个，总数恰好平衡），
  `handlers` 表**建得起来**、命令**注册得上**，可它引用的那些名字**从没被赋值** ⇒
  `attempt to call a nil value`，且**列区间正好等于注册处那次调用**的宽度（`DSH_players(m)`）。
- **为什么之前所有推断都跑偏**：那些"定义形式 / 200 局部量上限 / 顶层 return"的排除项**都是真的**，
  但**没一个是原因** —— 定义行本身**根本没执行**。台账里那条"矛盾证据"（`hand=function` 却另四个 nil、
  "跑到了表之后却没跑表之前"）**并不矛盾**：`hand` 是**更早**、在拼接点**之前**定义的，所以活着；
  新块里的四个在拼接点**之后**，死在 `setCount` 里。
- **证据链**（都可在离线复现，工具 ⇒ `MAINTENANCE.md` §1a）：
  1. `check_block_depth.js` 显示 `SHARED MOVE HELPERS` 那一段的块深度比预期深一层；
  2. `scan_exec.js` 在**运行中的字节**上：`setCount` / `draw` / `handlers` 都 `IN`，而
     `placeFace` / `takeOne` / `players` / `spawn` / `destroy` **全部 `NOT-IN`**；
  3. `debug.getlocal` 直接回答"它们**根本不是** local"（本来那条 `SCOPE ... takeOne=nil` 只说明值是 nil，
     说明不了**有没有这个名字**）；
  4. 修完 `verify_f8.js`：`DEFINITIONS=49 MISSING=0`；阴性对照（删掉收尾）立刻 `LOAD ERROR`。
- ⚠️ **为什么 7 条门禁全绿也看不见它**：`test_bridge_primitives.ps1` 的抽取块**起点在 1600 行附近**，
  也就是**在拼接点下方** ⇒ 它**整段跳过了那一大片死区**。**"门禁全绿"只证明它检查了的东西，
  从不证明"这块 chunk 装得上"** —— 这是本轮最值钱的一课。
- ✅ **已补上门禁**：`test_bridge_primitives.ps1` 新增第 2b 步 —— `verify_f8.js` 加载**整块桥接**，
  核对**每一条行首定义的函数**在加载后是否真的存在（判定看子进程写的 `VERDICT=` 状态文件，不看退出码）。
  **阴性对照已验**：把"平衡但错位"的坏版本装回去 ⇒ 该步转红、门禁 `exit 1`。
- ✅ **已修**：`tts\lua\dsh_global.lua`（`fix(lua): F8 ...`，`git diff --numstat` = 5 增 2 删）。
  ⚠️ **桥接烤在存档里** ⇒ 必须 `install_save2.ps1` 重烤 ＋ 玩家重载，活体才会变；重烤后 `ping` 应回 `v15-tags-snap-hand`。

<details>
<summary>原始排查记录（保留：里面的排除项和"矛盾证据"是这次定案的基础）</summary>

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

⚠️ **当时定的纪律**：在这些命令通过最小复现之前，一律按"活体不可用"对待 —— 离线门禁（含桩用例）**看不见这个问题**。

</details>

**F9 · `dsh_global.lua` 的行尾从"故意混用"漂移成了单一风格**（`⚠️`，2026-10-09）
**先说结论：`.gitattributes` 的字节一致性承诺没问题** —— 用可靠方法验过：`git diff HEAD -- <file>` 为空，且
`git cat-file -s HEAD:<file>` = **96789 B** ＝ 工作区文件（`.NET` 直读）**96789 B** ⇒ 逐字节相同。
（F8 修复后该文件是 **96791 B / 2048 行**——就是那 5 增 2 删，字节数对得上。）
⚠️ 但我一开始用**不可靠的方法**（`git show ... > 文件` 经 PowerShell 重定向落盘）得到"HEAD 是全 LF、工作区是全 CRLF"，
据此写下了"承诺被打破"的结论 —— **那是方法造成的假象**。教训：核对二进制/编码相关的事实，**必须走 `git cat-file -s`
与 `[IO.File]::ReadAllBytes`**，别用 shell 重定向。

**真实且仍待处理的部分**：该文件现在是 **全 CRLF、0 行裸 LF**，而 `.gitattributes` 的注释写明本仓库
**故意混用**（原为 1607 CRLF ＋ 93 裸 LF）。本次会话的多次"文本模式编辑"（丢掉 `\r` 再统一补成 CRLF）逐步把它推成了单一风格。
⇒ 功能无影响（`validate_lua.js`、TTS 都过），但**与文件自身声明的意图不符**。要处理的话应一次性决定统一到哪一种，
并用 `[IO.File]::WriteAllBytes` 写入（不经任何文本模式编辑）。
⚠️ **2026-10-11 复测 —— 上面那句要更正**：该文件现在是 **全裸 LF、0 行 CRLF**（`ReadAllBytes` 逐字节数出来 2029 × `\n` / 0 × `\r\n`），
与"全 CRLF"**正好相反** ⇒ 那句只是当时的一次快照，**别当现状**。`.gitattributes` 仍是 `* -text`（签出不转换）⇒ 功能上无所谓；
真该做的仍是**一次性决定统一到哪一种**（用 `[IO.File]::WriteAllBytes`，不经文本模式编辑），别让每次编辑把它推来推去。

## 4. 怎么续验（下一款 mod 来了照做）

1. 照 `tts\docs\BOOTSTRAP.md` §2 走"教一款新 mod"（存档 → 烤桥接 → `ping` → 索引 → `-Inventory` → `objects.json` → 地图）。
2. **照 §2 表逐行判**：`✅` 要写**命令 ＋ 回执**；失败就在 §3 记 `F<n>`（**记原始返回，别猜**）。
3. **专挑与上次不同的形态**（如：有骰盘的 vs 没有的 · 单人对面的 vs 多人的 · 有规则的 vs 纯沙盒）。
4. 回写本文件 §1 ＋ §2；**F1/F2 若被触发，就是新证据**，别当噪音。
