# TTS_RULES.md —— Tabletop Simulator 代玩规则与技术手册（**做 TTS 工作时读一次**）

> **什么时候读我**：任务是在 TTS 里替人打桌游（任何一款）时。
> **别的项目不要读我** —— 平台纪律在 `~/.dsh\AGENTS.md`（自动注入）。
> ⚠️ **别整份读**：按下面的路由表取要用的那节。本文件 = **规则 ＋ 工具 ＋ 能力边界 ＋ 坑**（原先的 `TTS_WORKFLOW.md` 已并入，2026-10-11）。
> 每回合那一份是 **`local\games\<游戏>\STATE.md`**（⛔ 不进仓库）；每回合通用动作 ⇒ `PLAY.md`。

| 我要干什么 | 读哪节 |
|---|---|
| 跟玩家怎么配合 / 响应窗口 / 隐藏信息 | **§一** |
| 找个脚本 / 判断"这脚本能不能动" | **§二**（工具清单**唯一真源**） |
| 一回合怎么走 | **§三** |
| 「结束回合」到底能不能程序按 | **§四**（**唯一真源**） |
| **"他刚才干了什么"** / 差分能识别什么 | **§五**（先看能力边界） |
| 改棋盘上的数字 / 挪棋子 / 计数器不动 | **§五**（5.2 计数器 · 5.3 移动 · 5.4 落板） |
| 换存档 / 桌上有什么 / **某物到底在哪** | **§六**（6.2 是标准动作） |
| 认一张牌 / 一个指示物 | **§六 6.3** —— ⚠️ **hash 不够**时看拼图那条 |
| 必须截图时 | **§七** |
| 给物件装 / 改游戏内 Lua | **§八（每次都要走那三步）** |
| **接手一款没见过的新 mod** | **§九**（含 ⚠️ 写入前 sanity check ＋ PowerShell 陷阱） |
| 撞上怪现象 | **§十** ＋ `MAINTENANCE.md` |

## 零、一句话原则（方法别选错）

> 核心教训：**不要用截图去反推坐标。** 游戏自己知道每个物件在哪；截图是给人看的，机器读它既慢又错。
> 外部调研（"AI 在 TTS 里打桌游"的先行研究）⇒ `PRIOR_ART.md`；三条直接相关的结论：公开实现 **0 个**；学术与工程都指向「**结构化状态 > 像素状态**」；**隐藏信息在 API 层拿不到**（会话状态、不落盘）⇒ 标准解是**请玩家把牌落到桌面**，读 `FaceURL` 认牌。

| 想做的事 | 该用的方法 | ⛔ 绝对不要 |
|---|---|---|
| 知道某物在哪 | `getPosition`（Lua）或存档 JSON | 截图上量像素 |
| 知道板上某点在桌面哪 | 板子 `positionToWorld()` | 手工算比例 |
| 知道某卡是什么 | `CustomDeck.<id>.FaceURL` 的 40 位 hash → 本地图缓存 | 靠截图辨认 |
| 知道板子多大 | `getBounds()` / `getVisualBoundsNormalized()` | 假设尺寸 |
| 知道板面图案在哪 | 按**颜色**识别（LockBits），**只作交叉验证** | 肉眼读缩略图 |
| 把棋子放对位置 | 先算，再 `getPosition` **回读**确认 | 放完就假定对了 |

## 一、跟人怎么配合

- **玩家（人类）= 座位上的另一个人**：只做两件事 —— ① 自己的决策 ② **结束回合**。**我 = 其余席位，全部棋子操作归我。**
- ⭐ **决策归玩家，操作归我**：把「**选项 ＋ 代价**」摆出来等他点，**绝不替他拍**；我自己的席位我自己决定。
- ⭐ **玩家每次宣告动作 = 给我一次「响应窗口」**（打牌 / 改骰 / 防守）⇒ **必须表态**（"我出牌 / 我不出牌"），别当成已定型直接结算。
- 沟通三条：**DSH GUI 聊天框** · **TTS 笔记本对话频道**（`ds.ps1 -Do tabread`）· 桌上实物。**都要看。**
- ⛔ **隐藏信息双向纪律**：① **不读**对手隐藏区（手牌/盖放/牌堆顶），**也不做位置推断**；② **我自己的也不说**。只报**已公开**的事实（移动 · 落点 · 计数 · 牌堆张数 · 已翻开的牌）。看桌面变化一律走 `diff_hidden.ps1 -Game <游戏>`（按 `cache\hidden_zones.csv` 折叠隐藏区）。
- ✅ **隐藏信息的标准解（能读且公平）**：请玩家把要公开的牌**落到桌面**（面朝下也行）—— 桥接读不到的只是"**容器里**的牌"；桌面上的牌我能读 `FaceURL` 的 hash ⇒ **他看不到牌面（公平）· 我能认牌（可决策）**。
- ⚠️ **不是一律"以话为准"，而是"以物为准"**：玩家的**读数**（骰面）是权威；**效果/结算主张**先记为**假设**，只有与 TTS 状态 diff 一致、或与公开牌面无矛盾时才升级为事实；**一有矛盾当场请他摊到桌面**，不靠嘴确认。
- 🚫 **默认不接 VLM/OCR**（`PRIOR_ART.md`）：一张卡一次视觉推理＝慢、有概率错；`FaceURL` hash **免费且确定**。只有"牌面朝下且必须当场认牌"才考虑。
- ⭐ **对手翻出的公开牌必须主动读**（事件牌/结算牌）：不读就无法核对计数。**别等他提醒。**
- ⚠️ **请玩家做动作的四条教训**（都踩过）：① **尽早要一个锚点**（请他拖个棋子到参照点，比任何图像分析都快准）；② **别连续试错放置**（每错一次就动一次他的棋盘）；③ **不确定就明说**（"我读图不可靠，请你看一眼"）；④ **别用截图判断棋子落在哪格**。

## 二、工具清单（`tts\*.ps1`，按频率 · **找脚本/清理时读我 —— 唯一真源**）

> 规则：**根目录只放现役工具**；死的/实验性的在 `~\.dsh\archive\tts-legacy\`（⚠️ **不在本仓库**，别再去找）。
> **改任何 `.ps1` 之后必须跑 `check_ps1.ps1`**（补 BOM ＋ 真解析器全量校验）。

### ⭐ 核心（每局都在用）

| 脚本 | 干什么 |
|---|---|
| **`play.ps1`** | **通用入口/分发器**：读 `GAME=` ⇒ 转发给该游戏的**控制层** `local\games\<game>\control\play.ps1`。✅ **没有控制层时 `status`（或裸调用）也能用**：桥接版本 · 物件数 · 在位玩家 · 轮到谁（2026-10-11 起） |
| **`ds.ps1`** | **跟 TTS 说话的高层入口**：`-Do 'ping / tabread / getState:<g> / setCount:<g>:<n> / act:<g>:<verb> / move:… / draw:… / all:<n> / read:<g>'`；v14 起 `players` · `take:<堆>:<CardID>:<x>:<y>:<z>` · `destroy:<g>` · `spawn:copy:<g>:…` · `player:<Color>:<turn\|blind>`；v15 起 `container:<g>` · `hand:<Color>:holding\|<give>\|<draw>` · tags/吸附点。**`spawn:type` 已被桥接显式拒绝**（见 §十） |
| **`roll.ps1`** | 掷/读骰面：**必须明说意图** `-Roll`（掷）/ `-NoRoll`（只读）；**裸调用 `exit 2` 且不接触 TTS** |
| `ttslib.ps1` · `ttsx.ps1` | **唯一的 TCP 传输层**（`ttslib` **dot-source，别 spawn**）· 原始通道（只回 `customMessage`） |
| `dsbatch.ps1` | 一条进程跑多条 `ds.ps1` 命令（`-Commands 'a;;b'`）⚠️ 两层子进程会被沙箱掐网络 ⇒ 优先逐条 |
| `say.ps1` | 往笔记本对话频道发一条（**中文走 `-MessageFile`**）；单进程就地 TCP |
| `live_index.ps1` · `diff_index.ps1` · **`diff_hidden.ps1`** | 整桌实时快照（CSV）· 差分（`-Snapshot` 冻结基线）· **带隐藏区遮蔽的 diff（对外显示一律用它）** |
| `card.ps1` | 查卡库 `cache\<game>_cards.md`（`-Q '<名字>'`）＋ 别名表；**无 `-Q` 只回用法 + `exit 2`** |
| `check_ps1.ps1` | **改完 `.ps1` 必跑**：补 BOM ＋ 真解析器校验（递归） |
| **`doctor.ps1`** | **新机器/新 clone 第一步**（只读体检）：PowerShell · 路径 · TTS 目录 · 39999 · node · **每请求注入字节数** |
| **`setup.ps1`** | **首次上手向导**（默认只读）：打印"到第一回合"的 8 步 ＋ 转给 `doctor.ps1`。`-InitGame <slug>` 从 `tts\templates\` 建 `local\games\<slug>\` 并把 `GAME=` 指过去（先备份）· `-DryRun 1` 预览 |
| **`tr.ps1`** | **交还回合**：`-To mine\|player` 搬那枚回合标记（`-State` 指定存档颜色）· 坐标取自 `cache\<game>_turn.json` |
| `tools\turn_calib.ps1` · `tools\turn_side.ps1` | 每款 mod **一次校准**（`-Discover`/`-Answer`/`-Show`）· 运行时判定**轮到谁**（`mine\|player\|unknown\|uncalibrated`） |
| `tools\turn_poller.ps1` | 后台作业：每 2.5 s 读位置、**变化才写** `cache\turn_side.txt` ⇒ 配 file 哨兵做**快速叫醒** |
| `tests\live_smoke.ps1` | **烤完桥接/重载后跑它**：17 条**只读**命令逐条 PASS/FAIL，一次看清哪个子集坏了（离线门禁测不出"命令在活体上到底能不能用"） |

### 🔧 常用（按需）

| 脚本 | 干什么 |
|---|---|
| `obj_index.ps1` | **存档侧**全量物件索引 → `cache\obj_index.csv`（含 url hash / `src` / **规则书 `pdfurl`** / 容器关系 / GMNotes；**滞后 ~5 分钟**）· `-Hist` 出名称直方图 |
| `guidinfo.ps1` | 给定 guid → 从存档切出 **CardID / deck / 位置**（**认牌用**） |
| `bags_dump.ps1` · `bag_list.ps1` | 展开容器（牌堆/袋）内容 → `cache\bag_contents.txt` |
| `bootstrap.ps1` | **换局/新存档**重新认物：默认只打座位表+摘要，全表写 `cache\session_map.md`（`-Full` 打全表）；认物规则**不在代码里** ⇒ 读 `local\games\<游戏>\objects.json`（schema ⇒ `BOOTSTRAP.md` §1b）。`-Inventory` ⇒ `cache\obj_inventory.md`（教新 mod 用） |
| `install_save2.ps1` | **写存档的唯一通道**（灌 `lua\dsh_global.lua` ＋ 修 notebook tab id；需一次提权）；日志写 `cache\install2_log.txt` |
| `crop_zoom.ps1` | 裁图 ＋ 放大转真 PNG（**读卡面/查图用**；`Mods\Images` 里扩展名常与真实格式不符） |
| `tts_api.ps1` | TTS **External Editor API（39999）** 原始客户端；`tools\exec_script.ps1` = 走它的 **`messageID 3`** 执行 Lua（**安全**，见 §十） |

### 💤 休眠但别删（删了会踩坑）

| 脚本 | 什么时候才需要 |
|---|---|
| `card_index.ps1` · `index_images.ps1` | 把**卡片映射到本地图缓存**（建卡库、认新牌面）—— 卡库已建好，平时不用 |
| `grab_window.ps1` | 抓 TTS 窗口像素（Unity 下 `PrintWindow` 无效，靠 BitBlt）；"没有 Lua 通道只能看画面"时的兜底 |
| `tts_click.ps1` | 合成鼠标输入。⚠️ **已定案：合成点击点不到 mod 的「结束回合」按钮** ⇒ 基本没用 |
| `front_watch.ps1` · `read_turn.ps1` | **旧叫醒链**（`cache\front.txt` ＋采样横幅色块）—— ⛔ **已被 `turn_poller.ps1` ＋ file 哨兵取代**（见 §四），保留但不接新东西 |
| `validate_lua.js` | **改 `lua\dsh_global.lua` 之前**必跑（并同时改 `DSH_VERSION`） |

### 🧪 离线测试（**不开 TTS 也能跑**）

7 条、唯一入口 `tts\tests\run_all.ps1`（"退出码 0 ＋ 输出含成功标志"才算过）⇒ 逐条清单 ⇒ `CONTRIBUTING.md` §3。
⚠️ 改测试判定逻辑前**先造一个"坏"的阳性对照**（本仓库两次"假绿"）。`check_ps1.ps1` 是递归的 ⇒ 测试自身也受校验。
📌 **活体那半**：`tests\live_smoke.ps1`（需要 TTS）。

### 目录与跨脚本引用（改名/清理前先看）

```
tts\  *.ps1 现役 · lib\bridge.ps1 通用传输包装 · lua\dsh_global.lua 桥接本体（别动）
      tools\ 跨语言小工具 · templates\ 新游戏三模板 · tests\ 离线门禁 ＋ 活体冒烟 · docs\ 全部文档
```
⚠️ 跨脚本引用：`bootstrap → ds/obj_index/live_index` · `diff_index → live_index` · `live_index → ds` ·
`read_turn → grab_window/tts_click` · `front_watch → read_turn` · `channel_watch/ttsx/roll/say → ttslib` ·
`play → ttslib/say` · `install_save2 → lua\dsh_global.lua` · `tr/turn_side/turn_poller → tools\exec_script ＋ cache\<game>_turn.json`。

### ⭐ 两层是怎么分开的

- **`tts\` = 通用层**（对任何 mod 都成立）：传话 `ttslib`/`ds`/`ttsx`/`say` · 看 `obj_index`/`live_index`/`diff_*` · 认物 `bootstrap`（数据在 `local\games\<游戏>\objects.json`）· 查卡 `card` · 写存档 `install_save2` · 传输包装 `lib\bridge.ps1`。
- **`local\games\<游戏>\control\` = 该游戏的控制层**（不进仓库，按 `BOOTSTRAP.md` §2 教出来）：`play.ps1`（入口，带自己的 `param()`）＋ 模块（`dice`/`rules`/`verbs`…）＋ 数据 `cache\<game>_rules.json`。
- ⇒ 换一款游戏 ＝ **加一个 `control\` 目录 ＋ 改 `GAME=` 一行**，仓库一行都不用动。
- ⛔ 控制层里**不许写死仓库路径**（配置由 `tts\config.ps1` 提供：`$DshGameControl`/`$DshLibTtslib`/`$DshLibBridge`/`$DshGameRules`）；**必须 UTF-8 带 BOM**（`local\` 不在 `check_ps1.ps1` 扫描范围内）。
- ✅ 判"桥接在不在"**永远**用 `ds.ps1 -Do ping`（版本号即凭据）—— **别拿 `play.ps1 <动词>` 当连通性检查**（它要先跑控制层，控制层可能在碰 TTS 之前就因缺文件失败，那是分层设计不是桥接断了）。

## 三、一回合怎么走

1. 读**那一份**：`local\games\<游戏>\STATE.md` = **这一局状态的唯一真源**（比分/资源/待办）＋ 该游戏 `FLOW.md`（规则/坐标）。
2. **核对盘面（一条命令拿实测值）**：**有控制层的游戏**用 `play.ps1 turn`（盘面＋骰面＋招式＋笔记本尾条，全只读）；
   ⚠️ **没有控制层的游戏**用 `play.ps1 status`（桥接版本/物件数/在位玩家/轮到谁）＋ 按 STATE 自己拼动词。⛔ 别照抄 `turn`（会 `NO PART`）。**别靠记忆。**
   （每次调用付一个 PowerShell 进程启动 ≈0.27-0.35 s ⇒ **合并命令就是省时间**）
3. **该我走**：按 STATE 待办 ＋ `FLOW.md` 的技能表，**一条命令一个阶段**。
4. 摆玩家的选项；我自己的行动直接执行。
5. 写回 STATE（**只改"当前"块与待办**，**≤5 KB**）→ 报一行公开事实 → **等哨兵叫醒**（不轮询）。

## 四、「结束回合」按钮 —— ⭐ **唯一真源**（要改只改这一节）

- ✅ 它就是右上角那块「**Player N**」横幅本身（悬停弹出"点击结束回合"）。
- ⛔ **我程序里按不了**：普通点击 / `-Absolute` / 绿星三种都试过全无效（**TTS 不吃合成输入**）。
  📌 本节是这条判定的唯一真源：`PLAY.md` · `USER_GUIDE.md` · `README*.md` · `BOOTSTRAP.md` **只留指针、不复述理由**。
- ✅ **可检测信号 = 桌上现成的回合标记（社区 Turn Tracker）**：玩家按它的 End Turn ⇒ 它**挪到另一侧**（`Locked=true`）。
  ⚠️ **那枚按钮在有的 mod 里不灵**（它调 `Player[color].getPlayerHand()`，某些 TTS 版本上失效）⇒ **让玩家直接拖棋子**，效果一样。
  判定"轮到谁"由**每款 mod 一次校准**得出：`tools\turn_calib.ps1`（`-Discover`/`-Answer`/`-Show`）+ 运行时 `tools\turn_side.ps1`。
  ⛔ **不要自己造标记件**：运行时 `spawnObject` 造自定义件会弹模态窗并挂住线程、烤进存档会被 TTS 丢弃（四条硬事实 ⇒ `VALIDATION.md` F11）。
  回合**流水**（第几回合）记在 `local\games\<游戏>\STATE.md`，**不另设计数器**（一处定义）。
- ✅ **自动叫醒（2026-10-11 换链）**：常驻作业 `tools\turn_poller.ps1`（每 **2.5 s** 读位置，**变化才写** `cache\turn_side.txt`）＋ **file 哨兵**（`pattern=^mine`，推送 <1 s）⇒ **检测 ~0.5-3.3 s**（实测一次 468 ms）。
  ⛔ **旧的 `front_watch.ps1` → `cache\front.txt` → `TURN=P<席位>` 已停用**（依赖"TTS 在前台"，切后台就读不到）。
  ⚠️ **`command` 哨兵**能用但平台 **~20 s** 才探一次（请求 15 s 无效；**5 s 会被饿死** ⇒ `BOOTSTRAP.md` §C）。
  ⚠️ 轮询器是**后台作业、不跨会话** ⇒ 新会话要重跑它并**重挂 file 哨兵（`max_fires` 必须显式给**，默认 1 次就没了）。命令 ⇒ `PLAY.md` 回合交接节。
- ⛔ **别用 `callx`/`Object.call` 驱动别的 mod**：实测**两次把 TTS 弄失联**，且**从未修复**（⇒ `VALIDATION.md` F12）。

## 五、能力边界：能读什么、能写什么

### 5.1 差分能识别什么（**读玩家操作**）

TTS **没有事件流**（订阅不到"他点了那张牌的快捷动作"），只能看**状态**：`diff_index.ps1 -Snapshot` 冻结基线 → 让他行动 → 再跑一次看差异。

| 变更类 | 实机能否识别 | 依据 |
|---|---|---|
| 新增 / 删除 | ✅ | guid 集合差 |
| 移动 | ✅ 位移 > **0.30** 世界单位（以下算物理抖动） | `diff_index.ps1` 容差 |
| 翻转 | ✅ rotZ 变化 > **25°**，并能判"翻开/盖上" | 同上 |
| **放进/拿出容器**（换父级） | ❌ **恒不触发** | 需要 `parent`，而 `live_index.ps1` 把它**硬编码为空** |
| **状态变化**（计数器 / `LuaScriptState` / GMNotes） | ❌ **恒不触发**（脚本会打印 `NOTE`） | 需要 `gm`/`ss`，同样为空 |

- 那两类真要读 ⇒ 走 **`obj_index.ps1`**（解析存档：正确，但 TTS **~5 分钟**才写一次）⇒ 不适合实时回合。
- **结构上识别不到**：容器内部 · 隐藏区（`diff_hidden.ps1` 故意折叠）· 纯点击无状态变化 · 两次快照间的**中间态** · 二选一的效果 · 意图/时序 · 牌面文字（只认 hash＋CardID）。
- ⇒ **差分是安全网，不是玩家报告的替代品**。纪律：他每次宣告 = **响应窗口**，**以他报的为准**（与 §一"以物为准"配合：矛盾时请他摊牌）。

### 5.2 Lua 沙箱的能力边界（实测）

`sandbox` 里 **`load` / `loadstring` / `eval` / `setUI` / `io` / `loadfile` 全是 nil** ⇒ 命令层必须是**显式白名单 + 手写分支**，不能动态构造调用。
已验可用 verb：`getPosition/setPosition` · `getRotation/setRotation` · `getScale/setScale` · `getBounds/getBoundsNormalized/getVisualBoundsNormalized` · `getGMNotes/setGMNotes` · `getName/setName` · `getDescription/setDescription` · `getColorTint/setColorTint` · `getLock/setLock` · `getValue/setValue` · `getQuantity` · `flip` · `shuffle` · `deal` · `setState/getStates` · `positionToLocal/positionToWorld` · `getScreenPosition`。
⚠️ **`setLuaScriptState` 不存在**（`script_state` 是**成员变量**，直接赋值）—— **且成员变量 verb 必须在"方法查找"之前处理**，否则误报 `object has no method ...`（绕了两轮）。

### 5.3 计数器的两种机制（别搞混）

| 机制 | 谁在用 | 读 | 写 |
|---|---|---|---|
| `GMNotes` | 资源计数器类 | `getGMNotes` | `setGMNotes` |
| `LuaScriptState` | MrStump 的 Universal Counter Token | `getScriptState` | `setScriptState`（值必须是合法 JSON，如 `{"saved_count":12}`） |

⚠️ 只改存档值**不会动屏幕上的数字**（脚本没重读）⇒ 要用 `setcount`（它走 `desc + customSet() + script_state` 并**回读**验证）。

### 5.4 移动物件的正确写法

```lua
o.setPosition({ x, y, z })          -- ✅ 直接位置参数
-- ❌ 通过通用 fn(o, {x=..,y=..,z=..}) 会报 "cannot convert a userdata to a clr type UnityEngine.Vector3"
```
⇒ `ds.ps1` 里 `move:`/`rotate:` 走**专用 handler**，**不要**用通用 `act:` 去调 `setPosition`。

### 5.5 「落在板子上」的判据

放完**一定回读** `getPosition`：板面高度 = 板中心 y + 板厚/2。棋子 y 明显高于它 = 在板上；接近桌面 y ≈ 2 = **掉到桌子上了**（曾把棋子放到板外：y 从 2.6 变 1.9）。

## 六、找物件与认牌

### 6.1 先建「物件索引」，别用 Lua 全扫描

**问题**：Lua `getObjects()` 只给顶层物件（袋子/牌堆里的拿不到）；而 `find:`/`count:` 这类**批量命令在 400+ 物件时会 15–90 秒超时**。
⚠️ **更正（2026-10-04）**：`find:` 从来不是"超时"—— **凡是返回列表的命令都发不出回复**，因为 `sendExternalMessage` 无法序列化嵌套表，而那句没包 pcall，整个回复流程静默死掉（**已修**：列表压成 JSON 字符串 + 包 pcall）。判别诀窍：**发一个不存在的命令**（一定回 `no handler`）；**命令已知却完全不回 = 就是这个 bug**。

**做法**：直接解析自动存档生成全量表（`obj_index.ps1` → `cache\obj_index.csv`；`bags_dump.ps1` 展开容器）。
关键实现要点：用 `JavaScriptSerializer`（**提高 `MaxJsonLength`**）解析，**不要用 `ConvertFrom-Json`**（带大 Lua 的存档会抛异常）；递归走 `ObjectStates`/`ContainedObjects`/`ChildObjects`/`States`；**袋里的物件在取出前不是顶层物件**，所以要展开容器；`ConvertFrom-Json` 出来是 PSCustomObject ⇒ **用 `$v.FaceURL`，不要 `$v['FaceURL']`**。
**查东西**：直接对 CSV 用 grep/Import-Csv，比任何 Lua 命令都快。

### 6.2 看全貌 + 定位「这东西到底在哪」

| 来源 | 结论 |
|---|---|
| **存档缩略图 `TS_AutoSave*.png`** | ❌ **实测只有 256×256**（文件 ~150 KB 全是未压缩像素）⇒ 只能做"有没有东西被挪动"的粗检 |
| **高分辨率俯视截图** | ✅ 正解：一张就能看清全部编号、计数器数字、卡面。玩家给，或 `grab_window.ps1 -Handle <hwnd>` 抓（抓的是**当前相机**，先把镜头拉到俯视） |
| 普通游戏内截图 | ⚠️ 只是当前视角，多半看不到全桌；一次 1–2k token，不如一张全貌图划算 |

**标定「世界 → 图素」**：俯视图是仿射的，**两个点对就够**：`img_x = OffX + Scale*world_x` · `img_y = OffZ - Scale*world_z`。
取两个**图上看得见、`obj_index.csv` 里有坐标**的物件当锚点，解 `Scale/OffX/OffZ`。
⚠️ **别用地图板边框当锚点** —— 可见图素常比 `getBounds()` 的碰撞盒大（本局差近一成）。

**定位任何一件东西的标准动作**：① `obj_index.ps1`（**确认打印的存档 mtime 是新的**）② 用 CSV 按特征筛（`name`/`scale`/`nick`/坐标区间）③ 找到候选 → **回读** `ds.ps1 -Do 'act:<guid>:getPosition'` 确认 ④ 图上认不出 → **`crop_zoom.ps1` 裁图放大**。
> **原则**：图用来**发现和缩小范围**；**精确坐标一律回读 `getPosition`**。**图是给人看的，数字要问游戏要。**

⚠️ **两条血泪教训**：① **别按"离某个参照点最近"判身份**（我把两座移动城市的归属弄反，还错报"某玩家城市放错 25 格"）⇒ **反投影成图素、裁图直读编号**；② **别把"我按推算值摆的东西"当成验证**（循环验证）。

### 6.3 认牌：**hash ＋ CardID**，不认名字

- 存档里卡片名字都是 `Card`/`CardCustom`，唯一身份是图片 URL：`CustomDeck.<CardID>.FaceURL` 尾段 **40 位十六进制 hash**。
- **同一图在不同主机域名不同**（`steamusercontent-a.akamaihd.net` vs `cloud-3.steamusercontent.com`）⇒ **匹配 hash，别匹配整条 URL**。
- 本地图缓存：`...\Mods\Images\<扁平化URL>.<ext>`（`card_index.ps1` / `index_images.ps1` 建映射）。
- ⭐⭐ **hash 不够：一张拼图可以装很多张牌**：`CardID = deckId*100 + 格号`（格号从 0 起，左到右、上到下）⇒ **`NumWidth*NumHeight > 1` 时，hash 相同的若干张是【不同的牌】**。
  （实例：8 张板共用拼图、`NumWidth=4,NumHeight=2` ⇒ 我按 hash 判"4 张一样的牌"并凭记忆贴名字，**全错**。）
- **规则**：① 认牌 = `FaceURL` hash **＋ `CardID`**（必要时加 `NumWidth/NumHeight`）；② **拿不到 `CardID` 就不要猜名字**（直说"不知道"或把拼图按格裁开看）；③ 查 `CardID` 用 `guidinfo.ps1 -Guid <g1>,<g2>`。
- ⛔ **不要让模型手抄 hash**（我把 48 个 hash 手打进 CSV，全是编的）⇒ 一定用工具从图里取。
- ⚠️ **不要用 `JavaScriptSerializer` 解析这些存档**（实测抛 `ArgumentException`，而且**异常会把整份 JSON 打进 stderr**，token 成本极高）⇒ 用正则截取。
- ⚠️ **`powershell -File x.ps1 -Guid a,b,c`** 会把 `a,b,c` 当**一个字符串**传进来，数组参数**不会**自动按逗号拆 ⇒ 脚本里自己 `-split ','`。（同类：`f $arr[0] $arr[1]` 会把整个数组绑给第一个参数。）

## 七、截图与窗口（只在必要时用）

> **省 token 纪律**：状态一律用 Lua 读，**不要用截图**。必须截图时：

```powershell
# 先按句柄抓（-TitleMatch 会抓到浏览器 —— DSH GUI 标题里也含 "Tabletop Simulator"）
& powershell -NoProfile -File 'tts\grab_window.ps1' -Handle <hwnd>
```
- 拿句柄：枚举可见窗口（EnumWindows + GetWindowText + GetWindowRect）找标题精确匹配的那个。
- `PrintWindow` 对 Unity 通常失败 ⇒ 脚本回退 `ScreenBitBlt` ⇒ **要求 TTS 在前台**，否则抓到压在它上面的窗口。
- 抓完先看字节数：几百字节 = 全黑/失败，几 MB = 成功。
- ⚠️ `grab_window.ps1` 引用的 `alt_activate.ps1` **已不在仓库**（归档）⇒ 要前台就**手动切**或用 `tts_click.ps1` 的护栏逻辑。

## 八、改游戏内 Lua 的安全流程（每次都要走）

```powershell
node tts\validate_lua.js tts\lua\dsh_global.lua        # 1) 语法校验（必跑！曾抓到 here-string 里字面量 `r`n）
& powershell -NoProfile -File 'tts\install_save2.ps1'  # 2) 从最新自动存档重建槽位（需 danger-full-access）
# 3) 让玩家 Menu → Load → <上一步写出的槽位>（槽位名以本次实际安装结果为准）
```
- `validate_lua.js` = luaparse（依赖：`npm i luaparse` 或设 `LUAPARSE_DIR`）。
- **PowerShell here-string 不转义反引号**：单引号 here-string 里写 `` `r`n `` 会原样进 Lua。
- **notebook 页 `id` 必须唯一**，否则 `getNotebookTabs()` 顺序不稳定、写入永远写偏。
- 写盘后 `ds.ps1 -Do ping` 的 **`loads=`** 会变 ⇒ 这是判断玩家是否重载过的依据。
- 存档目录在 workspace 之外 ⇒ 写盘需**单次提权**（预期行为）。
- 📌 改完**跑一次 `tests\live_smoke.ps1`**（离线门禁证明不了命令在活体上能用）。

## 九、接手一款没见过的新 mod：标准开局

```
1. ping / tabread                        → 确认连通 + 读玩家留言
2. obj_index.ps1 + bags_dump.ps1         → 全量物件表（本地 grep，别用 Lua 扫）
3. 找板子：getPosition/getRotation/getBounds → 记下中心、rotY、尺寸
4. ⭐ 坐标初始化：请玩家做一次校准动作（把棋子拖到明确参照点 → getPosition）
5. 认物：bootstrap.ps1 -Inventory → 写 local\games\<游戏>\objects.json → bootstrap.ps1 出地图
6. 算目标坐标 → move: → getPosition 回读   → 逐个确认落点
7. 写状态：setGMNotes / setScriptState     → 回读确认
8. say.ps1 汇报 + 请玩家确认                → 只问一次，别反复
```
（完整换 mod 流程 ⇒ `BOOTSTRAP.md` §2 ＋ §2b"教出控制层"。）

### ⚠️ 写入前的强制 sanity check（血的教训）

我曾把 `$OZ - $SZ*$py` 写成让 PowerShell 把 `-SZ` 当参数、`$py` 当**指数**，算出 **2.8×10²¹** 的坐标，把一个模型移过去后**被物理引擎销毁**。
**规矩：任何 `move:` 之前，先打印目标坐标并检查范围**（板子半宽用 `act:<boardGuid>:getBounds` **当场读**，别照抄旧数字）：

```powershell
if ([math]::Abs($x) -gt $half -or [math]::Abs($z) -gt $half) { Write-Host "REFUSED: ($x, $z) off the board"; exit 1 }
```

**配套的 PowerShell 陷阱（每条都实际咬过我）**：

| 写法 | 后果 |
|---|---|
| `$a - $b * $c` 在表达式/参数位 | `-b` 被当成**参数名**，`$c` 变指数 → 天文数字 |
| `[math]::Round($a - $b*$c, 3)` | 表达式求值失败或算错 |
| `f $arr[0] $arr[1]` | 整个**数组**绑给第一个参数 → "cannot convert System.Object[] to System.Double" |
| `$g` 之类单字母变量 + `-G` 参数 | 撞名，类型错乱 |
| here-string 里的 `` `r`n `` | 原样写进 Lua → 语法错误 |
| **含中文的 `.ps1` 存成无 BOM 的 UTF-8** | ⚠️ `powershell -File` 按 ANSI 读 ⇒ 中文乱码 ⇒ 报一堆 `Missing closing ')'`。**必须带 BOM** |
| 双引号串里再写 `"` | 字符串提前结束 ⇒ 解析失败（用 `「」` 或 `` `" ``） |
| 双引号串里的 `` `t ``（想写路径） | 反引号是转义符 ⇒ 被吃掉（改用单引号） |

**一律：先取成 typed 标量、显式加括号、写盘前打印验证。** 含中文的脚本写完**先空跑一次**。

> **另一类"陷阱"在数据**：某 mod 有 **5 个 `HandTrigger`** —— 四个在座位排（z≈−115）、一个离群的在 z=+114。**按 x 排序会把离群那个插进座位中间，让所有玩家归属整体错位。** ⇒ **凡"按某个坐标排序来分配身份"，先确认没有离群样本。**

## 十、⚠️ TTS 特有的坑（都付过代价）

- **牌在容器里读不到**：桥接只索引顶层物件 ⇒ 读手牌/牌堆内容要**请玩家把牌拖到桌上**；手牌计数板**不可信**（曾读数 3、实际 5）。
- **卡面文本读得到就别标"未确认"**：卡表大图在 `Mods\Images`，用 `crop_zoom.ps1` 裁格读图。
- ⛔ **`call:<guid>:<fn>` 对不存在的函数名也回 `ok=true`**（pcall 吞错）⇒ 写入只能"调用前后各读一次"判断。
- ⛔ **`callx` 会把 TTS 弄失联**（实测两次，**从未修复**）⇒ 别用它驱动别的 mod；要执行 Lua 用 `tools\exec_script.ps1`（官方 `messageID 3`，**安全**，但它跑在**空环境**里：读不到物件私有变量，且**返回值不回**、只能靠 `print`/`sendExternalMessage` 观察）。
- ⛔ **`spawn:type` 已被桥接显式拒绝**：`spawnObject` 造自定义件会让 TTS 弹模态「自定义板块」窗并挂住线程（三次尝试全失败 ⇒ `VALIDATION.md` F10）⇒ **要造物用 `spawn:copy`**（复制桌上现成件）。
- ⚠️ `ERR listener busy on 39998`（后台 watcher 抢端口）会成批出现 ⇒ **逐条重试**（`exec_script.ps1` 已内置 3 次重试）。
- ⚠️ `ERR TTS unreachable` **未必是 TTS 没开**：先探 **39999** 端口；OPEN ⇒ 是沙箱掐了**嵌套子进程**的网络 ⇒ 改用**本进程内联发送**。
  ⛔ **别用 `Get-Process` 判 TTS 开没开**（沙箱只看得到十几个进程；`Get-CimInstance` 直接拒绝访问）⇒ 看 **`Player.log` 的最后写入时间**更可靠。
- **`obj_index` 读存档、滞后 ~5 分钟**；`diff_index -Snapshot` 才是**实时**基线。
- ⛔ **对手隐藏区的 guid：只许知道"有没有变动"，绝不许拿去匹配身份**（拿它对上某张牌 = 偷看，被抓过）。
- **卡片身份 = `FaceURL` hash ＋ `CardID`**；TTS 叠放会**合并成 Deck**（旧 guid 失效、物件数下降 = **成功不是失败**）。
- **翻面看 `rotZ`**（180/270 = 面朝下），**掉头看 `rotY`** —— 别混。
- **`Infinite_Bag` 取物后数量不减** ⇒ 验证看**物件总数**（`ping`）；且**从袋里取出的 token 常常没有图案 ⇒ 这类摆放交给玩家**。
- ⚠️ **延迟/挂账效果不会自己冒出来**：卡面写"本回合收尾阶段…"的，**收尾第 1 步必须倒查本回合用过的牌有没有挂账**。
- 含中文的 `.ps1` 手写时**尽量用 ASCII 注释**；`check_ps1.ps1` 能补 BOM。

## 十一、换局 / 新游戏

- **冷启动 / 换局 / 换模组**：照 `tts\docs\BOOTSTRAP.md` 走（三种情形 ＋ 共同核心四步）；`ds.ps1 -Do ping` 是任何情形的第一步。
- **guid 全变** ⇒ 识别一律靠 **hash ＋ nick ＋ scale ＋ 坐标关系**，**绝不用记住的 guid**；上一局的坐标/常量一律作废（资源点上放什么常常是开局随机）。
- 换局后：改 `local\games\<游戏>\STATE.md` 的「当前」块、按需更新 `FLOW.md`，卡库/规则库按需重建；**新游戏骨架用 `tts\setup.ps1 -InitGame <slug>`**（别手抄模板）。
- 🕰️ 已终局那一局留下的**跨游戏通用教训**归档在 `local\archive\`（要重开那类游戏时看）。
