# MAINTENANCE.md —— 本仓库的维护要点（**动手改脚本 / 改流程之前读**）

> ⚠️ **2026-10-09 起，平台层已迁出仓库**：踩过的坑 ×15 · 上下文注入与隔离 · 各类工作区的注入量
> ⇒ 现在在 **harness home 的 `platform\MAINTENANCE.md`**（即 `$DSH_HOME\platform\`；路径不写死）。
> 本文件只留**和本仓库直接相关**的部分。

## 0. 平台要点 —— `OPENSOURCE-TEMP`（**开源前处理**）

<!-- ===== OPENSOURCE-TEMP: 平台要点 =========================================
     为什么在这：**本仓库要能独立成立** —— 开源用户手上**没有** harness-home 那份平台宪章，所以这几条必须随仓库走；本机开发时平台宪章**照旧注入**（发布时才用专属 profile 屏蔽，见 `tts\docs\INJECTION.md`）。
     ⇒ 别与平台宪章重复：**这里放"开源用户也需要"的**，本机专属的放 `AGENTS.local.md`。
     判据：这几条"换配置/换 harness/换机器就未必成立"，**不属于 TTS 领域内容**。
     开源前处理：① 删掉整块（推荐，若平台层会另行发布），或 ② 改成指向平台层的指针。
     查找：grep -rn "OPENSOURCE-TEMP" .
     ===== /OPENSOURCE-TEMP ================================================ -->

- 含中文的 `.ps1` **必须 UTF-8 带 BOM**；改完立刻跑 `tts\check_ps1.ps1`（递归补 BOM ＋ 真解析器校验）。
- 跑脚本一律 `powershell -NoProfile -ExecutionPolicy Bypass -File '<绝对路径>'`（`& xxx.ps1` 可能被策略挡下）。
- **写工作区之外**会报 `[sandbox: file access denied]` ⇒ 那是策略不是 bug，**一次提权重试**，别硬绕。
- 工具壳是 **Windows PowerShell 5.1** ⇒ 直接读中文文件会按 ANSI 解码成**乱码**（文件没坏）⇒ 加 `-Encoding UTF8` 或 `[IO.File]::ReadAllText`。
- 判端口用 `netstat -ano | findstr :39999`
- **沙箱限制子进程时的门禁姿势**（抓子进程输出走文件再读 · 别用 `Start-Process`）⇒ 见 `CONTRIBUTING.md` 的门禁小节。（⛔ `Get-NetTCPConnection` 在本沙箱会假报"没人在听"）。
- **火绒 HIPS 实测（2026-10-09，可复核）**：命中的规则是 `rp_name_execcreate_powershell_hidden`（"隐藏执行 PowerShell"），**触发者是 DSH 自己** —— 日志里 `p_procname = node.exe`（`dsh web` / `dsh-subprocess-local` / `dsh-sandbox-windows-acl`），被创建的是 `powershell.exe -NoLogo -NoProfile -NonInteractive -Command "<本次工具调用的脚本文本>"` ⇒ **每一次工具调用都是这个形状**，不是某条命令格外可疑。
  - **匹配很罕见、且是"间歇"的**：产品日志里该规则**总共只有 5 条**（18:53:47 · 18:54:16 · 18:55:54 · 18:59:16 · 20:13:58），而这两天经它起的 PowerShell 有几百次 ⇒ **不是每次工具调用都被拦**。⚠️ **触发条件未查明**：20:13:58 那次（唯一一条我确知"调用被掐"的：无输出、退出码 `-1`）恰是我把三种"隐藏执行"惯用法塞进同一条命令的探针，但**同一份惯用法组合在 20:19:18 重跑一遍完全正常、日志里连匹配都没有** ⇒ **"叠加才触发"这个说法已被自己推翻**（当时 n=1）。可用的只有相关性，不是机制。
  - `$.detail.action` 恒为 0、`$.detail.risk` 恒为 2（**不区分**）；`$.detail.treatment` 有 0/3 两种：我**已知被掐**的那次（20:13:58）是 **3**，上一场用户报"被掐"的 18:53/18:54 两条也是 **3**，而 18:55/18:59 两条是 **0** ⇒ **`treatment=3` 与"调用被掐"相关（n=3）**，但这是相关性、不是解码出来的枚举（规则库 `db\hips.db` 加密，`VARDYHFS` 头）。
  - **查法**（只读，不需要 GUI）：`C:\ProgramData\Huorong\Sysdiag\` 下 `log.db`（SQLite：表 `HrLogV3_60(fname,ts,detail)`，HIPS 事件 = `fname='sysprot'`，`detail` 是 JSON）与 `applog.db`（`AppRunInfoList_60` = 程序运行记录，⚠️ 它的 `ts` 是 **FILETIME** 不是 Unix 秒）。文件被占用 ⇒ 用 `FileShare.ReadWrite` 读，或 `sqlite3 -readonly`：
    ```powershell
    sqlite3 -readonly C:\ProgramData\Huorong\Sysdiag\log.db "select datetime(ts,'unixepoch','localtime'), substr(detail,1,200) from HrLogV3_60 where fname='sysprot' order by ts;"
    ```
  - **判据**：命令**无输出 ＋ 退出码 `-1`** ⇒ **先查上面那条 SQL 有没有对应时刻的 `sysprot` 行**：**有**（且 `treatment=3`）才是火绒，**没有**就是沙箱/别的原因（别再一律赖杀软）。
  - **"规范操作"能不能避免它？—— 本场证据说不支持这个因果**：三种惯用法**各自单独**用、一条 **7.3 KB 长内联命令**、以及**重跑同一份三种惯用法组合**，全部跑通且无匹配；而规则匹配的形状**永远是** harness 自己（`node.exe` ＋ `-NonInteractive` 隐藏起 PowerShell），agent 改不了。⇒ **别把"被掐"归因成"命令写得不规范"**；惯用法该避免（`Start-Process` 是沙箱自身的死路、`cmd /c` 是多余的一层），但那是**代码卫生**，不是这件事的成因。
  - ✅ **2026-10-09 20:14:04 用户改过火绒配置后，规则不再匹配**：该时刻 `Sysdiag\user.db` 被写入，之后 20+ 次工具调用（含上面全部探针）**零匹配**；此前的匹配频率约"每十几分钟一条"。⇒ **配置变更的时间点与"不再匹配"高度吻合**，但**没有审计线索**能证明因果（也读不出到底改了哪一项）。

## 1. 改完必须过的门禁（都在仓库里，**不需要 TTS**）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\run_all.ps1                  # ⭐ 入口：6 条全跑，要求"退出码 0 ＋ 输出含成功标志"
powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1                      # 补 BOM ＋ 真解析器
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_param_backfill.ps1      # param() 默认值必须有出处
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_diff_index.ps1          # 差分链离线自测
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_game_data.ps1           # 游戏数据必须在文件里、不在代码里
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_doc_refs.ps1            # 文档里的路径必须存在
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_agents_hygiene.ps1      # 指令槽的体积/漂移/泄露
```

⭐ **门禁绿了才提交**（别把"跑测试"和"提交"无条件串成一条命令）；改测试判定逻辑前，**先造一个"坏"的阳性对照**确认它真会红。

## 2. 本仓库的两个指令槽

| 槽 | 文件 | 上限 |
|---|---|---|
| 项目宪章 | `AGENTS.md` | **3,840 B** |
| 机器 overlay | `AGENTS.local.md`（**不进仓库**） | **2,048 B** |

第三个槽（跨项目平台宪章 `$DSH_HOME\AGENTS.md`）**本项目走 profile ⇒ 不注入**；它的源在平台层。

## 3. 路径与配置纪律

- 一律走 `tts\config.ps1`（`$WorkspaceRoot` / `$DshCache` / `$DshGameRules` / `$DshGameCards` …）；⛔ 不写死绝对路径 / 用户名 / 项目名。
- 本局数据在 `local\games\<游戏>\`（**不进仓库**）；该局规则数据 `cache\<游戏>_rules.json`。

## 4. 改代码的安全姿势（**两次真实截断事故换来的**）

`$ErrorActionPreference = 'Stop'` · **先全量校验锚点再统一写盘** · 写前兜底"内容短于 N 字符就拒绝写" · 能追加就别重写 · **`local\` 没有版本控制 ⇒ 改前先备份** · 逐文件 `edit` 优于一个脚本一次改多文件。细节见平台层 `MAINTENANCE.md` 的坑 14 / 15。
