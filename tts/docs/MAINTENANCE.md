# MAINTENANCE.md —— 本仓库的维护要点（**动手改脚本 / 改流程之前读**）

> ⚠️ **2026-10-09 起，平台层已迁出仓库**：踩过的坑 ×15 · 上下文注入与隔离 · 各类工作区的注入量
> ⇒ 现在在 **harness home 的 `platform\MAINTENANCE.md`**（即 `$DSH_HOME\platform\`；路径不写死）。
> 本文件只留**和本仓库直接相关**的部分。

## 0. 平台要点 —— `OPENSOURCE-TEMP`（**开源前处理**）

<!-- ===== OPENSOURCE-TEMP: 平台要点 =========================================
     为什么在这：**方案 A —— 机器上不放 `~/.dsh\AGENTS.md`**（已移为 `<harness home>\platform\AGENTS.md.disabled`）
     ⇒ 全局槽对**任何**启动方式都不注入（与 cwd/启动模式无关）⇒ 本项目要用的通用子集就近放这儿（另见本机 overlay）。
     判据：这几条"换配置/换 harness/换机器就未必成立"，**不属于 TTS 领域内容**。
     开源前处理：① 删掉整块（推荐，若平台层会另行发布），或 ② 改成指向平台层的指针。
     查找：grep -rn "OPENSOURCE-TEMP" .
     ===== /OPENSOURCE-TEMP ================================================ -->

- 含中文的 `.ps1` **必须 UTF-8 带 BOM**；改完立刻跑 `tts\check_ps1.ps1`（递归补 BOM ＋ 真解析器校验）。
- 跑脚本一律 `powershell -NoProfile -ExecutionPolicy Bypass -File '<绝对路径>'`（`& xxx.ps1` 可能被策略挡下）。
- **写工作区之外**会报 `[sandbox: file access denied]` ⇒ 那是策略不是 bug，**一次提权重试**，别硬绕。
- 工具壳是 **Windows PowerShell 5.1** ⇒ 直接读中文文件会按 ANSI 解码成**乱码**（文件没坏）⇒ 加 `-Encoding UTF8` 或 `[IO.File]::ReadAllText`。
- 判端口用 `netstat -ano | findstr :39999`（⛔ `Get-NetTCPConnection` 在本沙箱会假报"没人在听"）。

## 1. 改完必须过的门禁（都在仓库里，**不需要 TTS**）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1                    # 补 BOM ＋ 真解析器
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_param_backfill.ps1    # param() 默认值必须有出处
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_diff_index.ps1        # 差分链离线自测
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_doc_refs.ps1          # 文档里的路径必须存在
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_agents_hygiene.ps1    # 指令槽的体积/漂移/泄露
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
