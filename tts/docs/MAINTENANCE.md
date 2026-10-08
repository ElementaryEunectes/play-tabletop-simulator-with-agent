# MAINTENANCE.md —— 本仓库的维护要点（**动手改脚本 / 改流程之前读**）

> ⚠️ **2026-10-09 起，平台层已迁出仓库**：踩过的坑 ×15 · 上下文注入与隔离 · 各类工作区的注入量
> ⇒ 现在在 **harness home 的 `platform\MAINTENANCE.md`**（即 `$DSH_HOME\platform\`；路径不写死）。
> 本文件只留**和本仓库直接相关**的部分。

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
