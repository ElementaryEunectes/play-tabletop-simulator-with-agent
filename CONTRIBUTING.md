# CONTRIBUTING.md —— 改一个地方，要同时改哪些地方（**照着做就不会留下假文档**）

> **什么时候读我**：动手改**代码、目录结构、或任何被文档描述的行为**之前。
> 本项目的文档是**接口**：agent 靠它们找路。文档说谎比代码有 bug 更贵 —— 代码会报错，文档不会。

## 1. 两条铁律（先记住）

1. **开源边界**：**换个 TTS mod 还成立 ⇒ 进仓库；只对某一局成立 ⇒ 进 `local\games\<游戏>\`**。
   ⛔ 游戏名、guid、比分、卡面文本、规则数字**都不许出现在跟踪代码/文档里**（可执行代码里出现即违规）。
2. **一个读场合 = 一份文档**：新增 `.md` 必须①能一句话说清"什么时候读我"②读场合与现有文档**不重叠**③登记进 `tts\docs\README.md`。**预算见该索引（超 20 份必须先合并一份）**。

## 2. 改 X ⇒ 必须同时改 Y

| 你改了什么 | 必须同时改 | 机械检查会不会抓到你 |
|---|---|---|
| **移动/重命名任何被文档提到的文件** | 所有引用它的 `.md`（用 `grep` 搜旧名） | ✅ `tts\tests\test_doc_refs.ps1`（**会红**） |
| 改了桥接 Lua（`tts\lua\dsh_global.lua`） | `DSH_VERSION` ＋ `HANDOFF.md` §2/§4 ＋ **重装存档并请玩家重载** | ⚠️ 只有 `validate_lua.js` 查语法 |
| 改了「结束回合」按钮的**可行性判定** | ⛔ **只改 `tts\docs\TTS_RULES.md` §四**（唯一真源），其它文档只留指针 | ❌ 目前无检查 |
| 加了新的**原语**（桥接能力） | `TTS_RULES.md` §二 工具清单 ＋ `HANDOFF.md` §4 | ❌ |
| 加了新的**脚本** | `TTS_RULES.md` §二（按频率分类）＋ `tts\docs\README.md` 目录约定 | ❌ |
| 改了**每回合要走的路**（动词/哨兵） | `tts\docs\PLAY.md` ＋ `tts\docs\USER_GUIDE.md` | ❌ |
| 改了**启动方式**（`start.cmd` / `start-agent.ps1` / `<harness home>\platform\dsh_profile.ps1`）或 harness home | `AGENTS.md` 启动段 · `tts\docs\MAINTENANCE.md` 第二部分（注入机制 ＋ 工作区矩阵）· `README`／`USER_GUIDE` 的启动说明 | ❌（无测试守断言） |
| 改了 `AGENTS.md`（**每个请求都在计费**） | 跑 `tts\tests\test_agents_hygiene.ps1`（体积 ≤3.75 KB ＋ 5 个承载性指针） | ✅（**会红**） |
| 换了游戏 / 开了新局 | `local\games\_current.md` 的 **`GAME=` 行** ＋ 新建 `local\games\<游戏>\{STATE,FLOW,MYHAND}.md` | ❌（但脚本会报"no current game"） |
| 改了 `tts\config.ps1` 暴露的变量 | 用它的脚本（`grep` 变量名） | ❌ |

## 3. 提交前必跑（4 条，全部不需要 TTS）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tts\check_ps1.ps1                      # 递归补 BOM ＋ 真解析器
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_param_backfill.ps1      # 每个 '' 默认值有解或判空
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_diff_index.ps1          # 离线索引/差分
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_agents_hygiene.ps1      # 三个指令槽
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_doc_refs.ps1            # 文档里的路径必须存在
```

**测试是契约，不是装饰**：
- 改测试的判定逻辑时，**必须先造一个"坏"的阳性对照**，确认它真的会红（本项目已两次出现"校验器假绿/假红"）。
- 断言**行为**的文档改动，最好同时补一条断言（见第 2 条表里标 ❌ 的行）。

## 4. 改代码的安全姿势（**2026-10-08 一夜两次的教训**）

- **逐文件 `edit`**（先 `read` 再改），⛔ 不要用一个脚本一次改多个文件。
- 真要用脚本编辑：**① 开头 `$ErrorActionPreference = 'Stop'`；② 先全量校验锚点，再统一写盘；③ 写入函数兜底"内容短于 20 字符就拒绝写"**。
- **能追加就别重写**（`Add-Content` 按构造不可能截断）；**`local\` 没有版本控制** ⇒ 改前先 `Copy-Item` 备份。
- 改完**回读**关键行；跟踪文件坏了用 `git checkout HEAD -- <files>` 救。

详见 `tts\docs\MAINTENANCE.md`（本仓库要点）＋ harness home 的 `platform\MAINTENANCE.md`（坑 ×15 · 注入机制）。
