# TTS_RULES.md —— Tabletop Simulator 代玩规则（**做 TTS 工作时读一次**）

> **什么时候读我**：任务是在 TTS 里替人打桌游（任何一款）时。
> **别的项目不要读我** —— 平台纪律在 `~/.dsh\AGENTS.md`（自动注入）。
> 每款游戏的规则/坐标/状态在 `tts\docs\`（索引：`README.md`；**每回合那一份**：`<游戏>_STATE.md`，随身卡已并入）。

## 一、跟人怎么配合

- **玩家（人类）= P1**：只做两件事 —— ① 自己的决策 ② **点「结束回合」按钮**。**我 = 其余席位，全部棋子操作归我。**
- ⭐ **决策归玩家，操作归我**：玩家的选择必须把「**选项 ＋ 代价**」摆出来等他点，**绝不替他拍**；我自己的席位我自己决定。
- ⭐ **玩家每次宣告动作 = 给我一次「响应窗口」**（打行动牌 / 改骰 / 逼重掷 / 防守技）⇒ **必须表态**（"我出牌 / 我不出牌"），
  **不能当成他已经定型就直接结算**。
- 沟通三条：**DSH Web GUI 聊天框** · **TTS 笔记本对话频道**（`ds.ps1 -Do tabread`）· 桌上实物/图。**都要看。**
- ⛔ **隐藏信息双向纪律**：① **不读**对手隐藏区（手牌/盖放/牌堆顶），**也不做位置推断**；
  ② **我自己的隐藏信息也不说**（手里有什么牌 / 盖放了什么 / 下一步打算）。只报**已公开的事实**（移动 · 落点 · 计数 · 牌堆张数 · **已翻开的牌**）。
  看桌面变化一律走 **`diff_hidden.ps1 -Game <游戏>`**（按 `cache\hidden_zones.csv` 折叠隐藏区，从源头掐掉"看到了就顺手对上"）。
- ✅ **隐藏信息的标准解（能读、且公平）**：请玩家把要公开的牌**落到桌面中央**（面朝下也行）——
  桥接读不到的只是"**容器里**的牌"；桌面上的牌我能读 `CustomDeck.FaceURL` 的 **40 位 hash**（免费、确定）
  ⇒ **玩家看不到牌面（公平）· 我能认牌（可决策）**。步骤：① 请他拖到桌上（或贴图）② `obj_index.ps1`/`live_index.ps1` 取该 guid 的 `url`(hash)
  ③ `guidinfo.ps1 -Guid <g>` 认身份 ④ **只把"已公开"的那部分**写进 STATE。
- ⚠️ **不再一律"以话为准"，而是"以物为准"**：玩家的**读数**（骰面）依然是权威；但他的**效果/结算主张**先记为**假设（claim）**，
  只有 ① 与 TTS state diff 一致，或 ② 与公开牌面/其它独立声明**无矛盾**时才升级为事实；**一有矛盾就当场请他把东西摊到桌面可见区**（亮牌/摆 token），不靠嘴确认。
  （来源：arXiv 2510.25595 —— 信息不对称下带 verifier 的配置 89.3% vs 无 verifier 58.7%；我们搬的就是"verifier"这一半，训练那半搬不了。）
- 🚫 **默认不接 VLM/OCR**（PRIOR_ART §4③）：一张卡一次视觉推理 = 慢、有概率错、要模型权重；而 `FaceURL` hash 是**免费且确定**的。
  只有"**牌面朝下且必须当场认牌**"这种没有别的路的情形才考虑（`cloudwu/cardocr` 那条路线）。
- ⭐ **对手翻出的公开牌必须主动读**（事件牌/结算牌）：不读就无法核对计数、也预判不了局势。**别等他提醒。**


## 二、工具清单（`tts\*.ps1`，按使用频率 · **找脚本 / 清理时读我**）

> **什么时候读我**：想知道"这个脚本能不能动""有没有现成工具"时。
> 规则：**根目录只放现役工具**；死的/一次性的/实验性的在 **`~\.dsh\archive\tts-legacy\`**（33 个旧 `.ps1`，各自带 `README.md`）。
> ⚠️ 2026-10-08 更正：这个归档目录**不在本仓库里**（项目从 `~/.dsh` 迁出时没搬它），别再按 `..\archive\tts-legacy\` 去找。
> **改任何 `.ps1` 之后必须跑 `check_ps1.ps1`**（补 BOM ＋ 真解析器校验全部脚本）。

### ⭐ 核心（每局都在用）

| 脚本 | 干什么 |
|---|---|
| **`play.ps1`** | **通用入口 / 分发器**（几行）：读 `GAME=` ⇒ 找到该游戏的**控制层** `local\games\<game>\control\play.ps1` ⇒ **原样转发参数**。⭐**控制层**（不进仓库、由用户教出来）才是那个"一条命令一个阶段"的控制台：`turn`（回合开局：盘面＋骰面＋招式＋笔记本尾条，全只读）/ `status` / `income` / `roll` / `attack` / `defense` / `say`。写动词要显式开关（`-Apply` / `-Roll`）且支持 `-WhatIf`。**契约见下方方框** |
| **`roll.ps1`** | 掷/读骰面：`-Tray moon\|scar` —— **必须明说意图**：`-Roll` 才掷、`-NoRoll` 只读；**裸调用 `exit 2`（不接触 TTS）** |
| **`ds.ps1`** | **跟 TTS 说话的高层入口**：`-Do 'ping / tabread / getState:<g> / setCount:<g>:<n> / act:<g>:<verb> / move:… / draw:… / all:<n> / read:<g>'`。<br>⭐ **v14 新增（2026-10-09，补 F6 缺口）**：`players`（谁在桌上/轮到谁）· `take:<牌堆guid>:<CardID>:<x>:<y>:<z>[:<1\|0>]`（取**指定**那张，CardID 留空＝顶张）· `destroy:<guid>` · `spawn:copy:<guid>:<x>:<y>:<z>` / `spawn:type:<TTS类型>:<x>:<y>:<z>` · `player:<Color>:<turn\|blind>`。**spawn 的完整 JSON 走 `-Json`**（含冒号引号，命令行装不下）。
⭐ **v15 新增**：`container:<guid>`（列出 Bag/Deck 里的物件＋数量＋tags）· `hand:<Color>:holding|<give>:<guid>|<draw>:<容器guid>:<n>`（**摸牌进手/给牌**：`Deck.deal`，非牌堆回落 `dealToColorWithOffset`）· 标签与吸附点走 `act`：`act:<g>:setTags:标签1+标签2` · `act:<g>:addTag/removeTag/hasTag:…` · `act:<g>:setSnapPoints:x,y,z;x,y,z` · `act:<g>:use_snap_points:<true\|false>`。⚠️ **TTS 的 tag 是哈希**：`getTags` 回哈希、`setTags` 也要喂哈希（从带该标签的物件上抄）。|
| `dsbatch.ps1` | 一条进程跑多条 `ds.ps1` 命令（`-Commands 'a;;b'`）；⚠️ 两层子进程会被沙箱掐网络，优先 `ds.ps1` 逐条 |
| `ttsx.ps1` · `ttslib.ps1` | 原始通道（只回 `customMessage`）＋ **唯一的 TCP 传输层**（`ttslib` **dot-source，别 spawn**） |
| `say.ps1` | 往笔记本对话频道发一条（**中文走 `-MessageFile`**）；**单进程就地 TCP**（2026-10-08 去掉两次子进程 `ds.ps1`，每条消息省 ~0.9s） |
| `live_index.ps1` · `diff_index.ps1` | 整桌**实时**快照（CSV）· 差异（`-Snapshot` 冻结基线） |
| **`diff_hidden.ps1`** | **带隐藏区遮蔽的 diff —— 对外显示一律用它**（规则在 `cache\hidden_zones.csv`） |
| `card.ps1` | 查卡面文本库 `cache\<game>_cards.md`（`-Q '<名字>'`），别名表 `cache\<game>_alias.json`（英文/简写 → 牌名）；**无 `-Q` 只回一行用法 + `exit 2`**（以前是 PowerShell 自己吐 600 字节的强制参数报错）。两份路径都能用 `-CardsFile` / `-AliasFile` 覆盖（测试与"另一款游戏"用） |
| `front_watch.ps1` | 后台：写 `cache\front.txt`（前台状态 ＋ `TURN=Pn`）→ 配 file 哨兵叫醒 |
| `channel_watch.ps1` | 后台：写 `cache\chan.txt`（笔记本尾部变化 → `NEW`）→ 配 file 哨兵 |
| `check_ps1.ps1` | **改完 `.ps1` 必跑**：补 BOM ＋ 真解析器校验 |
| **`doctor.ps1`** | **新机器 / 新 clone 第一步**（**只读**体检）：PowerShell · 路径解析 · TTS 目录 · 39999 端口 · node · **每请求注入字节数** ⇒ `VERDICT: ready` 或带修复建议的问题清单 |

> ### ⭐ 两层是怎么分开的（2026-10-09 落到目录上）
> **`tts\` = 通用层**（对任何 mod 都成立）：传话 `ttslib`/`ds`/`ttsx`/`say` · 看 `obj_index`/`live_index`/`diff_*` ·
> 认物 `bootstrap`（数据在 `local\games\<游戏>\objects.json`）· 查卡 `card` · 写存档 `install_save2` ·
> **传输包装 `tts\lib\bridge.ps1`**（薄：发一条命令、按错误码转成值或失败）。
> **`local\games\<游戏>\control\` = 该游戏的控制层**（不进仓库，由用户按 `BOOTSTRAP.md` §2 教出来）：
> `play.ps1`（入口，带自己的 `param()`）＋ 任意模块（`dice`/`rules`/`verbs`…）＋ 数据 `cache\<game>_rules.json`。
> **`tts\play.ps1` 只是分发器**：解析 `GAME=` ⇒ dot-source 控制层 ⇒ `& $DshGameControl @args`。
> ⇒ 换一款游戏 ＝ **加一个 `control\` 目录 ＋ 改 `GAME=` 一行**，仓库一行都不用动。
> ⚠️ 控制层里**不许写死仓库路径**：配置由 `tts\config.ps1` 提供（`$DshGameControl` · `$DshLibTtslib` · `$DshLibBridge` · `$DshGameRules`）。
> ⚠️ 控制层**必须 UTF-8 带 BOM**（`local\` 不在 `check_ps1.ps1` 的扫描范围里，没人替你补）；`play.ps1` 里有一条 BOM 自检。
> 📖 **判据与实测证据** ⇒ `VALIDATION.md`；**怎么教一款** ⇒ `BOOTSTRAP.md` §2 与 §2b。
> ✅ 判"桥接在不在"**永远**用 `ds.ps1 -Do ping`（版本号即凭据）—— **别拿 `play.ps1 <动词>` 当连通性检查**：
> 它要先把控制层跑起来，控制层可能在**碰 TTS 之前**就因缺文件/缺数据失败（那是分层设计，不是桥接断了）。
> ❌ 没有 `control\` 目录 + `cache\<game>_rules.json` 的游戏 ⇒ 控制层的动词**根本跑不了**（会报 `NO PART`）；
> 这种 mod 上能用的只有 §一/§二 的**通用层** 与 `ds.ps1` 的原语。

### 🔧 常用（按需）

| 脚本 | 干什么 |
|---|---|
| `obj_index.ps1` | **存档**侧全量物件索引 → `cache\obj_index.csv`（含 url hash / **url 来源 `src`** / **规则书 `pdfurl`** / 容器关系 / GMNotes；**滞后 ~5 分钟**）。输出默认 2 行，名称直方图加 **`-Hist`**（25 行，按需） |
| `guidinfo.ps1` | 给定 guid → 从存档里切出 CardID / deck / 位置等身份字段（**认牌用**） |
| `bags_dump.ps1` · `bag_list.ps1` | 展开容器（牌堆/袋）内容 → `cache\bag_contents.txt` |
| `bootstrap.ps1` | **换局/新存档**时重新认一遍关键物件（guid 全变的场合）：**默认 stdout 只打座位表 + 摘要**，全表写进 `cache\session_map.md`；要打全表加 **`-Full`**。认物规则**不在代码里** ⇒ 读 `local\games\<游戏>\objects.json`（schema：`BOOTSTRAP.md` §1b）；**没有它就报错并指出路径**。教一款新 mod：`bootstrap.ps1 -Inventory` ⇒ `cache\obj_inventory.md`（name/nick/图 hash 直方图）|
| `install_save2.ps1` | **写存档的唯一通道**（把 `lua\dsh_global.lua` 灌进存档 ＋ 修 notebook tab id；需一次提权） |
| `crop_zoom.ps1` | 裁图 + 放大转真 PNG（**读卡面/查图用**；`Mods\Images` 里扩展名常与真实格式不符） |
| `read_turn.ps1` | 采样 mod 横幅色块 → `PLAYER=n`（TTS 不在前台时报 `NOTFOREGROUND`，**不给假数据**） |

### 💤 休眠但别删（只在特定情形才用 —— 删了会踩坑）

| 脚本 | 什么时候才需要 |
|---|---|
| `card_index.ps1` · `index_images.ps1` | 要把**卡片映射到本地图缓存**时（建卡库、认新牌面）—— 现在卡库已建好，平时不用 |
| `grab_window.ps1` | 抓 TTS 窗口像素（**Unity 下 `PrintWindow` 无效，靠 BitBlt**）；被 `read_turn.ps1` 引用；"没有 Lua 通道、只能看画面"时的兜底 |
| `tts_click.ps1` | 合成鼠标输入。⚠️ **已定案：合成点击点不到 mod 的「结束回合」按钮** ⇒ 基本没用；但 `front_watch.ps1` 默认参数引用它，**动它要连 `front_watch` 一起改** |
| `tts_api.ps1` | TTS **External Editor API（39999）** 原始客户端；协议表在它文件头。`ds.ps1`/`ttsx.ps1`（40000 消息通道）是主路，这个是退路 |
| `validate_lua.js` | **改 `lua\dsh_global.lua` 之前**必跑（并同时改 `DSH_VERSION`） |

### 🧪 测试（**不开 TTS 也能跑**）

6 条、唯一入口 `tts\tests\run_all.ps1`（"退出码 0 ＋ 输出含成功标志"才算过）⇒ **逐条清单与限制见 `CONTRIBUTING.md` §3**；每条测试的**头部注释**说明自己验什么。
`tests\fixtures\` = 合成数据（**不是真实存档**）· `tests\fake_live_index.ps1` = 冒充 `live_index.ps1` 的桩。
⚠️ 改测试判定逻辑前必须先造一个"坏"的**阳性对照**（`test_param_backfill.ps1` 第一版就因正则锚在行首而**完全看不见**单行 `param(...)`）；`check_ps1.ps1` 是**递归**的 ⇒ 测试自身也受 BOM ＋ 真解析器校验。

### 目录

```
tts\
├── *.ps1            现役脚本（本文件就是它的清单）
├── validate_lua.js  改 Lua 前的校验器
├── lua\             dsh_global.lua（桥接本体，install_save2.ps1 依赖，别动）· dsh_panel.lua
└── docs\            所有文档（索引 docs\README.md；本文件 docs\TTS_RULES.md；每回合那一份 docs\<游戏>_STATE.md）
```

⚠️ **跨脚本引用**（改名前先看这里）：`bootstrap → ds/obj_index/live_index` · `diff_index → live_index` ·
`live_index → ds` · `read_turn → grab_window/tts_click` · `front_watch → read_turn（＋ tts_click 参数）` ·
`channel_watch/ttsx/roll → ttslib` · `play → ttslib/say` · `install_save2 → lua\dsh_global.lua`。

## 三、一回合怎么走

1. 读**那一份**：`tts\docs\<游戏>_STATE.md` = **唯一真源**（比分/资源/待办）＋ **随身卡**（控制台动词 · 每回合步骤）—— 换局时「当前在玩哪个游戏」也写在它里面。
   现在玩哪款写在它开头的「现在这款 / 去哪读」一节。
2. **核对盘面**：**一条命令**拿实测值 —— 任何 mod 都是 **`play.ps1 turn`**（盘面 ＋ 我的骰面 ＋ 可打招式 ＋ 笔记本尾条，**全只读**）；
   别的游戏用 `status` 类命令。**别靠记忆**。（每次调用都要付一个 PowerShell 进程启动 ≈0.35s ⇒ 合并命令就是省时间）
3. **该我走**：按 STATE 待办 ＋ `<游戏>_FLOW.md` 的技能表，**一条命令一个阶段**。
4. 摆玩家的选项；我自己的行动直接执行。
5. 写回 STATE（**只改"当前"块与待办**）→ 报一行公开事实 → **等哨兵叫醒**（不轮询）。

## 四、「结束回合」按钮 —— ⭐ **唯一真源**（已定案；**要改只改这一节**）

- ✅ 它就是右上角那块「**Player N**」横幅本身（悬停弹出"点击结束回合"）。
- ⛔ **我点不了**：普通点击 / `-Absolute` / 绿星三种都试过全无效（TTS 不吃合成输入）。**目前永远由玩家点。**
  📌 **本节是这条判定的唯一真源**：`PLAY.md` · `USER_GUIDE.md` · `README*.md` · `BOOTSTRAP.md` **只留指针、不复述理由**（否则解决它的那天要改 9 份文档 19 处）。
  ⇒ 哪天有人真把那个按钮按下去了：改**这一节** ＋ `tts\lua\dsh_global.lua`（要重装存档并请玩家重载）＋ 跑 `tts\tests\` 四个测试；**别处不用动**。
- ✅ **另有可检测信号（v13-turntoken）**：桥接可造一个**自制回合令牌** —— `{cmd="turn_token"}`（自举一次）建/修它；点一下它就把回合号写进**昵称**（`DSH-TURN <n>`）、存进 `script_state`、并翻转 180°。
  读取：`{cmd="turn_state"}`（只读，回 `turn`/`nick`）或直接 `diff_index.ps1`（**`nick` 现在参与差分**，报 `NICK (昵称变化)`）。
  意义：**mod 的横幅仍点不了**，但"玩家结束了回合"从此**在存档里留痕** ⇒ 不再依赖 `front_watch.ps1` 的前台判据（TTS 不在前台时它读不出 `TURN`）。⚠️ 需**重装存档并请玩家重载**才生效（见 `HANDOFF.md` §7.9）。
- ✅ **自动叫醒**：`front_watch.ps1` 后台把"前台状态 ＋ `TURN=Pn`"写进 `cache\front.txt` → file 哨兵 pattern `TURN=P<我的席位>`
  ⇒ 玩家一点完就自动叫醒我。⚠️ sentinel 的 `command` 探测跑在只读沙箱（`Add-Type` 必崩）⇒ **只能 file 探测 ＋ 外部写文件**。
- ⚠️ TTS 不在前台时 `front.txt` 只剩 `OTHER/TTSFRONT`（读不出 TURN）⇒ **轮次要靠 STATE ＋ 盘面计数交叉判断**，别只看它。

## 五、⚠️ TTS 特有的坑（都付过代价）

- **`roll.ps1` 要求明说意图**：`-Roll` 才掷、`-NoRoll` 只读（源码 `if ($Roll) { act:<guid>:roll }`）；
  **裸调用直接 `exit 2` 且不接触 TTS**（2026-10-08 加的护栏）。`play.ps1 roll` 同理：**不加 `-Roll` 是只读**。
  以前默认会掷，我把它当"读"用过，把玩家的实际投掷反复重掷，**玩家当场抓到**。
  ⇒ **骰子判定以玩家报的为准**；我要读只用 `-NoRoll`，要真掷先问。
- **牌在容器里读不到**：桥接只索引**顶层物件** ⇒ 读手牌/牌堆内容要**请玩家把牌拖到桌上**（或贴图）；
  手牌计数板这类**不可信**（曾读数 3、实际 5 张）。
- **卡面文本读得到就别标"未确认"**：卡表大图在 `Mods\Images`，几何记在卡库 `§0`；用 `crop_zoom.ps1` 裁格读图。
- **`call:<guid>:<fn>` 对不存在的函数名也回 `ok=true`**（pcall 吞错）⇒ 写入只能"调用前后各读一次"判断。
- ⚠️ `ERR listener busy on 39998`（后台 watcher 抢桥接端口）会成批出现 ⇒ **逐条重试**。
- ⚠️ `ERR TTS unreachable` 未必是 TTS 没开：先探 **39999** 端口；OPEN ⇒ 是沙箱掐了**嵌套子进程**的网络，
  改用**本进程内联发送**或直接调 `ds.ps1`。**别用 `Get-Process` 判 TTS 开没开**（沙箱只看得到十几个进程；`Get-CimInstance` 直接拒绝访问）。
- **`obj_index` 读存档、滞后 ~5 分钟**；`diff_index -Snapshot` 才是**实时**基线。
- ⛔ **对手隐藏区的 guid：只许知道"有没有变动"，绝不许拿去匹配身份**（拿它对上某张牌 = 偷看，被抓过）。
- **卡片身份 = `FaceURL` hash ＋ `CardID`**（拼图 hash 相同 ≠ 同一张牌）；TTS 叠放会**合并成 Deck**（旧 guid 失效、物件数下降 = 成功不是失败）。
- **翻面看 `rotZ`**（180/270 = 面朝下），**掉头看 `rotY`** —— 别混。
- **`Infinite_Bag` 取物后数量不减** ⇒ 验证看**物件总数**（`ping`）；且**从袋里取出的 token 常常没有图案 ⇒ 这类摆放交给玩家**。
- ⚠️ **延迟/挂账效果不会自己冒出来**：卡面写"本回合收尾阶段…"的，**收尾第 1 步必须倒查本回合用过的牌有没有挂账**。
- 含中文的 `.ps1` 手写时**尽量用 ASCII 注释**（PS 5.1 把无 BOM 文件按 ANSI 读 ⇒ 中文注释变乱码并**语法报错秒挂**；`check_ps1.ps1` 能补 BOM）。
- 🕰️ 已终局那一局留下的**跨游戏通用教训**已归档在 `local\archive\` 下该局手册的 §18.10（要重开那类游戏时看）。

## 六、换局 / 新游戏

- **冷启动 / 换局 / 换模组**：照 `tts\docs\BOOTSTRAP.md` 走（三种情形 ＋ 共同核心四步）；`ds.ps1 -Do ping` 是任何情形的第一步。
- **guid 全变** ⇒ 识别一律靠 **hash ＋ nick ＋ scale ＋ 坐标关系**，**绝不用记住的 guid**；上一局的坐标/常量一律作废
  （资源点上放什么常常是开局随机）。
- 换局后：改 `tts\docs\<游戏>_STATE.md` 开头的「现在这款」，新建 `<游戏>_FLOW.md`，卡库/规则库按需重建。
