# MAINTENANCE.md —— 本仓库维护要点（**动手改脚本 / 改流程之前读**）

> 平台层（坑 ×17 · 上下文注入与隔离 · 各类工作区的注入量）⇒ **harness home 的 `platform\MAINTENANCE.md`**（`$DSH_HOME\platform\`，路径不写死）。本文件只留**和本仓库直接相关**的。
> 🧭 **代码/工具那半都在这**：找脚本 ⇒ **§5 工具清单** · 改游戏内 Lua ⇒ **§6** · 写入前 sanity check ＋ PowerShell 陷阱 ⇒ **§7**。

## 0. 本机 / 本沙箱要点 —— `OPENSOURCE-TEMP`（**开源前处理**）

<!-- OPENSOURCE-TEMP: 平台要点 —— 本仓库要能独立成立（开源用户手上没有 harness-home 那份宪章），所以这几条必须随仓库走；
     本机专属的放 `AGENTS.local.md`，别与平台宪章重复。开源前：① 删掉整块（推荐）或 ② 改成指向平台层的指针。查找：grep -rn "OPENSOURCE-TEMP" . -->

- 含中文的 `.ps1` **必须 UTF-8 带 BOM**；改完立刻跑 `tts\check_ps1.ps1`（递归补 BOM ＋ 真解析器校验）。
- ⚠️ **丢 BOM ＝ 会固化乱码，顺序错了会毁文件（2026-10-09 真事故）**：编辑工具常悄悄去掉 BOM ⇒ 此时**用工具壳跑这个 `.ps1`**，PS 5.1 按 ANSI 解中文 ⇒ `Unexpected token`；紧接着跑 `check_ps1.ps1`（本意是补 BOM），它把**已乱码的内容**原样写回并加上 BOM ⇒ **乱码被永久固化**。
  ⇒ 正确顺序：**① 先跑一次该脚本确认解析/行为正常 → ② 再补 BOM（字节级）→ ③ 最后才 `check_ps1.ps1`**；读文件一律 `[IO.File]::ReadAllText`。
  ⇒ **纯 ASCII 的文件对 BOM 免疫**（`tts\tests\test_agents_hygiene.ps1` 的淘汰名单就用"运行时按码位拼字"写成纯 ASCII，并自带一条"本文件除 BOM 外不得有非 ASCII 字节"的自检）。
- 跑脚本一律 `powershell -NoProfile -ExecutionPolicy Bypass -File '<绝对路径>'`；**工具壳是 Windows PowerShell 5.1** ⇒ 读中文文件要 `-Encoding UTF8` / `[IO.File]::ReadAllText`（否则乱码，文件没坏）。
- 写工作区之外 ⇒ `[sandbox: file access denied]`（**策略不是 bug**，一次提权重试）；判端口用 `netstat -ano | findstr :39999`（`Get-NetTCPConnection` 在本沙箱假报"没人在听"）。
- **沙箱限制子进程时的姿势**：抓子进程输出**写文件再读**（`& x 2>&1` 静默丢输出、退出码仍是 0）· ⛔ 别用 `Start-Process`（隐藏控制台 → `0xC0000142`）。门禁已改**同进程调用**、不再 spawn 内层 PowerShell ⇒ 受限模式下 7 条全绿（清单 ⇒ `CONTRIBUTING.md` §3）。
- ⛔ **`spawnObject` 造"自定义件"必须带内容参数，否则 TTS 会弹「自定义板块」窗口跟你要贴图**（2026-10-09 实测 + 官方文档）：
  `Custom_Tile`/`Custom_Token`/`Custom_Model`/`Custom_Board`/`CardCustom`/`DeckCustom` 这些**自定义**类型，
  `spawnObject({type="Custom_Tile"})` **不带 `image`** ⇒ 游戏主线程被那个模态窗口挂住 ⇒ **回执永远不来**、脚本改动随后被回滚。
  ⇒ 内置件（`Block`·`Checker`·…）不需要内容参数、不弹；**要造东西优先两条路**：
  ① **`clone`**（`spawn:copy`，复制桌上现成件 —— 不弹窗、活体验过）；② 真要新造 ⇒ 参数一次给全（`image=` 等，取自存档里同类的 `CustomImage`）。
  📄 依据：`api.tabletopsimulator.com/custom-game-objects/`；社区同类反馈 `tabletopsimulator.nolt.io/2326`（"spawnObject 弹自定义窗口"）。
- ⛔ **别给 `$LASTEXITCODE` 赋值**（2026-10-09 实测，害了一次假红）：在**函数里**写 `$LASTEXITCODE = $null`
  本意是"清掉上一次的值"，实际是**让 PowerShell 建了一个同名的普通局部变量**，它**遮住**了那个自动变量 ——
  而外部命令更新的是**自动变量** ⇒ 之后再读**永远是空**。实测：先赋值 → `[]`；不赋值 → `[0]`。
  ⇒ 直接读、不赋值；要在同一次调用里保证新鲜度，清 `[System.Environment]::ExitCode` 或干脆**让子进程自己写状态文件**
  （`verify_f8.js` 就是这么做的：`VERDICT=PASS|FAIL` 落盘，调用方读文件判，不碰退出码）。
- **火绒 HIPS（2026-10-09 实测）**：命中规则 `rp_name_execcreate_powershell_hidden`，**触发者永远是 harness 自己**（`node.exe` ＋ `-NonInteractive` 隐藏起 PowerShell）⇒ **每次工具调用都是这个形状**，agent 改不了。
  - 匹配**罕见且间歇**：日志里该规则**总共 5 条**（18:53:47 · 18:54:16 · 18:55:54 · 18:59:16 · 20:13:58），而这两天起了几百次 PowerShell。**触发条件未查明** —— "叠加惯用法才触发"这条结论**已被重复实验推翻**（同一份组合重跑正常、无匹配）。
  - 可用的是相关性：**已知被掐的调用带 `treatment=3`**（`action` 恒 0、`risk` 恒 2，不区分；规则库 `db\hips.db` 加密 ⇒ 枚举读不出来）。
  - **查法**（只读、不用 GUI）：`C:\ProgramData\Huorong\Sysdiag\log.db`（SQLite，表 `HrLogV3_60`，HIPS = `fname='sysprot'`，`detail` 是 JSON；文件被占用 ⇒ `FileShare.ReadWrite` 或 `sqlite3 -readonly`）。`applog.db` 的 `AppRunInfoList_60` = 程序运行记录，⚠️ 其 `ts` 是 **FILETIME**：
    `sqlite3 -readonly C:\ProgramData\Huorong\Sysdiag\log.db "select datetime(ts,'unixepoch','localtime'), json_extract(detail,'$.detail.treatment'), substr(detail,1,160) from HrLogV3_60 where fname='sysprot' order by ts;"`
  - **修法**（把"看不到的拦截"变回可见）：给 `node.exe` · `@deepseek-ai\dsh\` · `powershell`/`pwsh`/`cmd`/`git` · `~\.dsh\` · `%TEMP%\dsh-*` · 工作区**加信任**，或把该规则从"阻止"改成**询问/允许**。⚠️ **效果未单独验证**（用户 20:14:04 改配置后零匹配，时间吻合但因果未证）⇒ 换机器照做即可，别当成"已证有效"。
  - **判据**：**无输出 ＋ 退出码 `-1`** ⇒ 查上面那条 SQL 有没有对应时刻的 `sysprot` 行：**有**（`treatment=3`）才是火绒，**没有**就是沙箱/别的原因 ⇒ **别一律赖杀软，也别归因成"命令写得不规范"**。
  - 2026-10-09 20:14:04 用户改配置后 **20+ 次调用零匹配**（时间吻合、**因果未证**，读不出改了哪一项）。

## 1. 改完必须过的门禁

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\run_all.ps1   # ⭐ 唯一入口：7 条；"退出码 0 ＋ 输出含成功标志"才算过，空输出 = NOT RUN
```
⭐ **门禁绿了才提交**；改测试判定逻辑前**先造一个"坏"的阳性对照**确认它真会红（本仓库已两次出现"假绿"）。逐条清单/限制 ⇒ `CONTRIBUTING.md` §3。
- ⚠️ **`bridge primitives (Lua)` 这条门禁要先有 `fengari`**（JS 里的 Lua 虚拟机；本机没有 lua 二进制，TTS 也不自带可调用的）：
  `npm i fengari --cache local\scratch\luatest\.npm-cache --prefix local\scratch\luatest`（**缓存必须落在工作区内**，默认 npm 缓存目录在沙箱外会被拒）。缺它时门禁报 `fengari not found` 并以退出码 2 失败 —— **是 NOT RUN，不是 PASS**。
  它跑的是 `gen_bridge_primitives_test.js` → `tts\tests\gen_bridge_primitives.lua` → `run_lua.js`；**生成物必须与源文件一致**，门禁会重生成一次并对齐（不一致即红）。

### 1a. 诊断 Lua 桥接的 Node 工具（`tts\tools\`）

桥接是**烤进存档**的 ⇒ 活体上改不动、看不见；这几个工具让"它到底加载成什么样"在离线可复现。
`run_lua.js` = fengari 跑一个 `.lua`（门禁用）· `gen_bridge_alone_test.js` = 从**运行中脚本**或本地文件生成桩环境。

- `run_and_capture.js <lua> <outFile>` —— **抓子进程输出的唯一可靠姿势**（见 §0）。⛔ `execFileSync` 在本沙箱会**抛出且 stdout/stderr 都是空的**，那读起来和"子进程什么都没打印"一模一样 —— F8 排查时为这个假信号白花了一轮。
- `scan_exec.js [from] [to]` —— 逐条**行首语句**打标记，报告 `IN` / `NOT-IN`（**两个都打印**，因为"没打印"太容易被读成"没执行"）。
- `check_block_depth.js <file>` —— 打印每一条行首语句的**块深度**、末尾是否平衡。F8 的根因就是一处错位：少一个 `end` ⇒ **250 行变成了某个函数的函数体**，而总数恰好还是平衡的 ⇒ **能编译、能加载、名字全是 nil**。深度表一眼就能看出"从哪一行起进了不该进的层"。
- `verify_f8.js`（回归检查，**已进门禁流程之外、手动跑**）—— 加载仓库里的桥接，核对**每一条行首定义的函数**在加载后是否真的存在（阴性对照：把 `setCount` 的收尾删掉 ⇒ 立刻报 `LOAD ERROR`）。
- ⚠️ **工具自己先归一 `\r\n`**：这些文件是 CRLF ⇒ `readFileSync(...).split('\n')` 会让每行**末尾带 `\r`**，于是
  ① `^local ` 这类行首判定**全部失配**、② 往行尾追加语句会追加到 `\r` **之后** ⇒ 注入的标记**永远不到达**，
  看起来就像"这段代码根本没执行"——**这正是 F8 排查里那个假线索的成因**。凡按行处理都要 `.replace(/\r\n/g, '\n')`。
- ⛔ **量行尾不能用 PowerShell 重定向**：`git show HEAD:f > x` 会**被 PowerShell 自己改写行尾**，量到的是 PS 的产物不是 blob。
  用 `git_blob_eol.js <repo> <rev> <file> <tmpfile>`（`execFileSync` 配 `stdio:['ignore', fd, 'ignore']` —— 本沙箱**抓不到子进程 stdout**，只能让它写文件）。
  同类：`git_blob_cmp.js` 判断"blob 与工作区**是否只差行尾**"（归一后比 sha256）。
  2026-10-10 实例：`edit` 工具把一份 **LF** 的 `dsh_global.lua` 写成了 **CRLF** ⇒ git 把整个文件算成改写（**2023 行**，
  而真实改动是 15 增 402 删）。`git diff --numstat` 一出现"增删数 ≈ 文件总行数"就是这个病，**改回 LF 再 amend**（见 §4）。

## 1b. 速度：先量再改（**基线 = 一个 PowerShell 进程 271 ms**）

> **什么时候读我**：觉得某个脚本慢 / 要给每回合加命令时。**每多一个进程就是 +271 ms**，比 TTS 往返（~140 ms）更贵。

| 脚本 | 实测 | 备注 |
|---|---|---|
| 空 `powershell` 进程 | **271 ms** | 一切开销的地板 |
| `card.ps1 -Q` | 460 ms | 纯文件查 |
| `ds.ps1 -Do ping` | 530 ms | ＋一次桥接往返 |
| `tools\turn_side.ps1` | **620 ms**（改前 1028） | 曾是**子进程**调桥接 ⇒ 改**同进程** |
| `tr.ps1 -To player` | **~900 ms**（改前 12,921） | 见下面第 2 条陷阱 |
| `play.ps1 status` | 697 ms | 同进程，但发 3 条命令（ping/players/turn_tracker） |

**两个已修的陷阱（都值得记）**：
1. ⛔ **别为了调桥接再 spawn 一个 `powershell`**：`tools\turn_side.ps1` 原本这样写 ⇒ **1028 ms**，而它在**轮询器里每 2.5 s 跑一次**（占空比 40%）。
   正解 = **dot-source `tts\ttslib.ps1` ＋ `tts\lib\bridge.ps1` 就地发**（`play.ps1 status` 与 `tests\live_smoke.ps1` 就是这么写的）⇒ 620 ms，占空比降到 25%。
   （先 dot-source 再定义 `Fail`/`Err-Code` 两个桩，`Bridge` 的硬错误路径才不会撞空函数。）
2. ⛔ **别"坐满回执窗口"**：`tools\exec_script.ps1` 原来等满 `ListenSec`（12 s）才收工 ⇒ **`tr.ps1` 要 12.9 s**。改成**收到第一条回执就退出** ⇒ 0.9 s。
   ⇒ 写"发一条、等回复"的工具时，**默认应当早退**，只在需要多条消息（如 print ＋ sendExternalMessage）时才多等一小会儿。
3. 📌 一次要发**多条**命令时用 `dsbatch.ps1`（一条进程跑 N 条）。

## 2. 三个指令槽（**上限写在门禁里，不在这里复述**）

| 槽 | 文件 | 现状 |
|---|---|---|
| 跨项目平台宪章 | `$DSH_HOME\AGENTS.md`（源：`platform\HARNESS_HOME_AGENTS.template.md`） | **照旧注入**（发布时用专属 profile 屏蔽 ⇒ `tts\docs\INJECTION.md` §4） |
| 项目宪章 | `AGENTS.md` | 受门禁约束 ＋ 必含 5 个承载性指针 |
| 机器 overlay | `AGENTS.local.md`（**gitignore**） | 只放本机事实 |

## 3. 路径与配置纪律

- 一律走 `tts\config.ps1`（`$WorkspaceRoot` / `$DshCache` / `$DshGameRules` / `$DshGameCards` / `$DshGameAlias` / `$DshGameObjects` …）；⛔ 不写死绝对路径 / 用户名 / 项目名。
- **本局数据 ⇒ `local\games\<游戏>\`**（不进仓库；`objects.json` = 认物数据）· 规则 `cache\<游戏>_rules.json` · 卡库 `cache\<游戏>_cards.md` · 别名 `cache\<游戏>_alias.json`。

## 4. 改代码的安全姿势（**两次真实截断事故换来的**）

`$ErrorActionPreference = 'Stop'` · **先全量校验锚点再统一写盘** · 写前兜底"内容短于 N 字符就拒绝写" · 能追加就别重写 · **`local\` 没有版本控制 ⇒ 改前先备份** · 逐文件 `edit` 优于一个脚本一次改多文件。细节 ⇒ 平台层 `MAINTENANCE.md` 坑 14/15。
- ⚠️ **不许顺手改行尾**：`.gitattributes` = `* -text` ⇒ **签出不做任何转换**，仓库里**故意混用 CRLF / LF**（有的文件本身就是混合的）。改写文件的工具若把行尾归一，就是把"一行修复"变成**整文件 diff**（2026-10-09：改 2 行注释变成 95 增 95 删）。
  ⇒ 改完先看 `git diff --numstat <file>`：**增删数远大于你想改的行数 ⇒ 行尾或编码被动过了**，立刻 `git checkout HEAD -- <file>` 重来；要改中文只想动几行时，用**字节级字符串替换**而不是整文件重写（替换串本身不含行尾即安全）。
  📌 2026-10-10 **又犯一次**（`edit` 工具写 `dsh_global.lua` 时统一了行尾）⇒ **`edit`/`write` 工具也会动行尾**，不只批量替换；
  提交前用 `git diff --numstat` 复核一遍，事后用 `tts\tools\git_blob_eol.js` 确认**提交进去的那份**行尾没变（`git show` 的结果经 PS 重定向不可信）。
- ⛔ **`edit`/`write` 工具还会吃掉 UTF-8 BOM**（2026-10-11 实测两次）：只改几行注释，`tts\tests\test_doc_refs.ps1` 与 `tts\tr.ps1` 的 BOM 就没了（`git diff --numstat` **看不出来** —— 它不在文本 diff 里）⇒ **改完任何 `.ps1` 一律跑 `check_ps1.ps1`**，它会报 `BOM-FIXED` 并补回；"含中文必须带 BOM"这条规矩在编辑工具面前**不会自动成立**。
  自查法：`[IO.File]::ReadAllBytes($f)[0..2] -join ','` == `239,187,191`（或与 `git show HEAD:<file>` 对拍）。

## 5. 工具清单（`tts\*.ps1`，按频率 · **找脚本 / 判断"这脚本能不能动"时读我 —— 唯一真源**）

> 规则：**根目录只放现役工具**；死的/实验性的在 `~\.dsh\archive\tts-legacy\`（⚠️ **不在本仓库**，别再去找）。
> **改任何 `.ps1` 之后必须跑 `check_ps1.ps1`**（补 BOM ＋ 真解析器全量校验）。

### ⭐ 核心（每局都在用）

| 脚本 | 干什么 |
|---|---|
| **`play.ps1`** | **通用入口/分发器**：读 `GAME=` ⇒ 转发给该游戏的**控制层** `local\games\<game>\control\play.ps1`。✅ **没有控制层时 `status`（或裸调用）也能用**：桥接版本 · 物件数 · 在位玩家 · 轮到谁（2026-10-11 起） |
| **`ds.ps1`** | **跟 TTS 说话的高层入口**：`-Do 'ping / tabread / getState:<g> / setCount:<g>:<n> / act:<g>:<verb> / move:… / draw:… / all:<n> / read:<g>'`；v14 起 `players` · `take:<堆>:<CardID>:<x>:<y>:<z>` · `destroy:<g>` · `spawn:copy:<g>:…` · `player:<Color>:<turn\|blind>`；v15 起 `container:<g>` · `hand:<Color>:holding\|<give>\|<draw>` · tags/吸附点。**`spawn:type` 已被桥接显式拒绝**（见 `TTS_RULES.md` §七） |
| **`roll.ps1`** | 掷/读骰面：**必须明说意图** `-Roll`（掷）/ `-NoRoll`（只读）；**裸调用 `exit 2` 且不接触 TTS** |
| `ttslib.ps1` · `ttsx.ps1` | **唯一的 TCP 传输层**（`ttslib` **dot-source，别 spawn**）· 原始通道（只回 `customMessage`） |
| `dsbatch.ps1` | 一条进程跑多条 `ds.ps1` 命令（`-Commands 'a;;b'`）⚠️ 两层子进程会被沙箱掐网络 ⇒ 优先逐条 |
| `say.ps1` | 往笔记本对话频道发一条（**中文走 `-MessageFile`**）；单进程就地 TCP |
| **`channel_watch.ps1`** | **把笔记本对话频道变成哨兵能盯的文件**：轮询 `tabread` → `cache\chan.txt`（`<TAG> <chars> <时间> \| <尾部>`），配 **file 哨兵**（`pattern=^NEW \d`）⇒ 玩家写字就叫醒我。⚠️ 它**不 spawn `ds.ps1`**（两层子进程会被沙箱掐网络）⇒ dot-source `ttslib.ps1` 就地 TCP；换局要**重启**它并**重挂哨兵**（⇒ `BOOTSTRAP.md` §1 唤醒机制） |
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
| `tts_api.ps1` | TTS **External Editor API（39999）** 原始客户端；`tools\exec_script.ps1` = 走它的 **`messageID 3`** 执行 Lua（**安全**，见 `TTS_RULES.md` §七） |

### 💤 休眠但别删（删了会踩坑）

| 脚本 | 什么时候才需要 |
|---|---|
| `card_index.ps1` · `index_images.ps1` | 把**卡片映射到本地图缓存**（建卡库、认新牌面）—— 卡库已建好，平时不用 |
| `grab_window.ps1` | 抓 TTS 窗口像素（Unity 下 `PrintWindow` 无效，靠 BitBlt）；"没有 Lua 通道只能看画面"时的兜底 |
| `tts_click.ps1` | 合成鼠标输入。⚠️ **已定案：合成点击点不到「结束回合」**（玩家那块是桌上的**社区件 Turn Tracker**；TTS 自带那块在屏幕**顶部正中** ⇒ 详见 `TTS_RULES.md` §三） |
| `front_watch.ps1` · `read_turn.ps1` | **旧叫醒链**（`cache\front.txt` ＋采样横幅色块）—— ⛔ **已被 `turn_poller.ps1` ＋ file 哨兵取代**（见 `TTS_RULES.md` §三）。⚠️ 而且 `read_turn.ps1` **本体至今仍是坏的**（批量替换事故的残骸：`$hotsDir` / `$ilentlyContinue` / `$img.$Dispose()` / `$ist` —— **解析器查不出来**，那是运行期错不是语法错）⇒ **别调用它**；要复用就先逐行还原或连同 `front_watch.ps1` 一起归档（⇒ `VALIDATION.md` F4） |
| `validate_lua.js` | **改 `lua\dsh_global.lua` 之前**必跑（并同时改 `DSH_VERSION`） |

### 🧪 离线测试（**不开 TTS 也能跑**）

7 条、唯一入口 `tts\tests\run_all.ps1`；判据/清单/限制 ⇒ **§1** ＋ `CONTRIBUTING.md` §3（**不复述**）。
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
- **`local\games\<游戏>\control\` = 该游戏的控制层**（不进仓库，按 `BOOTSTRAP.md` §2b 教出来）：`play.ps1`（入口，带自己的 `param()`）＋ 模块（`dice`/`rules`/`verbs`…）＋ 数据 `cache\<game>_rules.json`。
- ⇒ 换一款游戏 ＝ **加一个 `control\` 目录 ＋ 改 `GAME=` 一行**，仓库一行都不用动。
- ⛔ 控制层里**不许写死仓库路径**（配置由 `tts\config.ps1` 提供：`$DshGameControl`/`$DshLibTtslib`/`$DshLibBridge`/`$DshGameRules`）；**必须 UTF-8 带 BOM**（`local\` 不在 `check_ps1.ps1` 扫描范围内）。
- ✅ 判"桥接在不在"**永远**用 `ds.ps1 -Do ping`（版本号即凭据）—— **别拿 `play.ps1 <动词>` 当连通性检查**（它要先跑控制层，控制层可能在碰 TTS 之前就因缺文件失败，那是分层设计不是桥接断了）。

## 6. 改游戏内 Lua 的安全流程（每次都要走）

```powershell
node tts\validate_lua.js tts\lua\dsh_global.lua        # 1) 语法校验（必跑！曾抓到 here-string 里字面量 `r`n）
& powershell -NoProfile -ExecutionPolicy Bypass -File 'tts\install_save2.ps1'  # 2) 从最新自动存档重建槽位（需 danger-full-access）
# 3) 让玩家 Menu → Load → <上一步写出的槽位>（槽位名以本次实际安装结果为准）
```
- `validate_lua.js` = luaparse（依赖：`npm i luaparse` 或设 `LUAPARSE_DIR`）。
- **PowerShell here-string 不转义反引号**：单引号 here-string 里写 `` `r`n `` 会原样进 Lua。
- **notebook 页 `id` 必须唯一**，否则 `getNotebookTabs()` 顺序不稳定、写入永远写偏。
- 写盘后 `ds.ps1 -Do ping` 的 **`loads=`** 会变 ⇒ 这是判断玩家是否重载过的依据。
- 存档目录在 workspace 之外 ⇒ 写盘需**单次提权**（预期行为）。
- 📌 改完**跑一次 `tests\live_smoke.ps1`**（离线门禁证明不了命令在活体上能用）。

## 7. 写入前的强制 sanity check ＋ PowerShell 陷阱（**每条都实际咬过**）

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
