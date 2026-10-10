# MAINTENANCE.md —— 本仓库维护要点（**动手改脚本 / 改流程之前读**）

> 平台层（坑 ×17 · 上下文注入与隔离 · 各类工作区的注入量）⇒ **harness home 的 `platform\MAINTENANCE.md`**（`$DSH_HOME\platform\`，路径不写死）。本文件只留**和本仓库直接相关**的。

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
