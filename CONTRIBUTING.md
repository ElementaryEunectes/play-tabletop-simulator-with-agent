# CONTRIBUTING.md —— 改一个地方，要同时改哪些地方（**照做就不会留下假文档**）

> **什么时候读我**：动手改**代码、目录、或任何被文档描述的行为**之前。
> 本项目的文档是**接口**：agent 靠它们找路。**文档说谎比代码有 bug 更贵** —— 代码会报错，文档不会。

## 1. 两条铁律

1. **开源边界**：**换个 TTS mod 还成立 ⇒ 进仓库；只对某一局成立 ⇒ 进 `local\games\<游戏>\`**。⛔ 游戏名 / guid / 比分 / 卡面文本 / 规则数字**不许出现在跟踪文件里**。
2. **一个读场合 = 一份文档**：新增 `.md` 必须 ①一句话说清"什么时候读我"②读场合与现有文档不重叠 ③登记进 `tts\docs\README.md`。

## 2. 改 X ⇒ 必须同时改 Y

| 你改了什么 | 必须同时改 | 机械检查 |
|---|---|---|
| 移动/重命名任何被文档提到的文件 | 所有引用它的 `.md`（grep 旧名） | ✅ `test_doc_refs.ps1` |
| 桥接 Lua（`tts\lua\dsh_global.lua`） | `DSH_VERSION` ＋ `HANDOFF.md` §4 ＋ **重装存档 ＋ 请玩家重载** | ⚠️ 只有 `validate_lua.js` |
| 「结束回合」的可行性判定 | ⛔ **只改 `TTS_RULES.md` §四**（唯一真源），别处只留指针 | ❌ |
| 新**原语**（桥接能力） | `TTS_RULES.md` §二 ＋ `HANDOFF.md` §4 | ❌ |
| 新**脚本** | `TTS_RULES.md` §二 ＋ `tts\docs\README.md` 目录约定 | ❌ |
| **每回合要走的路**（动词/哨兵） | `tts\docs\PLAY.md` ＋ `USER_GUIDE.md` | ❌ |
| **启动方式** 或 harness home | `AGENTS.md` 启动段 · `INJECTION.md` · `README`/`USER_GUIDE` | ❌ |
| `AGENTS.md`（**每请求都计费**） | 跑 `test_agents_hygiene.ps1`（体积 ＋ 5 个承载性指针） | ✅ |
| 换游戏 / 开新局 | `local\games\_current.md` 的 `GAME=` 行 ＋ 该游戏的 `{STATE,FLOW,MYHAND}.md` | ❌（脚本会报 "no current game"） |
| `tts\config.ps1` 暴露的变量 | 用它的脚本（grep 变量名） | ❌ |

## 3. 提交前必跑（**唯一入口**，6 条，都不需要 TTS）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\run_all.ps1    # "退出码 0 ＋ 输出含成功标志"才算过；空输出 = NOT RUN
```
6 条 = `check_ps1`（补 BOM ＋ 真解析器）· `param backfill`（每个 `''` 默认值有出处）· `diff chain`（差分链离线自测）· `game data`（**游戏数据必须在文件里、不在代码里**）· `doc refs`（文档里的路径必须存在）· `instruction hygiene`（三个指令槽的体积/漂移/隐私）。

- ⛔ 抓子进程输出**一律写文件再读**（`& x 2>&1` 会静默丢输出、退出码仍是 0）· ⛔ 别用 `Start-Process`（隐藏控制台 → `0xC0000142`）。
- ✅ **门禁一律同进程调用、不 spawn 子 PowerShell**（2026-10-09 起）：受限沙箱会拦"命令**及其后代**"里的 `powershell.exe`，而那个 spawn 本来就多余 ⇒ **6 条在受限模式下全绿，不再需要完全权限**。做法：被判脚本**不用顶层 `exit`**（改 `return`；调用方 `& ... 6>&1` 抓 `Write-Host`；契约由 `test_diff_index.ps1` case 8 用**解析器 token** 钉死）。例外：**stdout 就是结果**的终端工具（`card.ps1` / `bootstrap.ps1`）保留 `exit`。
- 沙箱 / HIPS / 编码等本机细节 ⇒ `tts\docs\MAINTENANCE.md` §0。

## 4. 安全姿势与「一处定义」

- 逐文件 `edit`（先 `read` 再改），⛔ 别用一个脚本一次改多文件；**能追加就别重写**；**`local\` 没有版本控制 ⇒ 改前先备份**；改完**回读**关键行；跟踪文件坏了用 `git checkout HEAD -- <files>` 救。
- ⭐ **一处定义、他处引用**：判定/常量/路径/阈值**只在一处**定义；**文档不复述判定**，只留指针（"见 X §N"）—— 同一事实写两遍 = 迟早不一致。
- **命名自检**：新函数名先 `Get-Alias` —— `rd del rm mv cp cat echo` 是内置别名且**优先于函数**（叫 `Rd` 的"读取"函数真删过 4 个文件）；⚠️ 参数名还要避开**公共参数别名** `db ea ev wa wv ov ob pv vb ia iv`（`Get-Alias db` **看不见**它，`-Db` 会直接被拒）。
- **按字节不按字符**：`$t.Length` 是**字符**数 ⇒ 中文会被误判（本项目误拦过 3 次），用 `UTF8.GetByteCount` / `(Get-Item).Length`。
- **同进程 `&` 调别人的脚本**：`exit` 在**脚本文件**里会被该文件自己的边界接住（调用者**不死**，码只进 `$LASTEXITCODE`），但它丢掉了"返回值"语义 ⇒ 工具/库脚本用 `return <码>` 或 `throw`（**只有没有脚本边界的 `exit`**，如 `iex`／手贴代码，才会**当场结束进程**）。
- ⭐ **门禁绿了才提交**（⛔ 别把"跑测试"与"提交"无条件串成一条命令）；改测试判定逻辑前**先造一个"坏"的阳性对照**确认它真会红（已两次出现"假绿"）。
- 细节 ⇒ 本仓库 `tts\docs\MAINTENANCE.md`（§4）· 平台层 `platform\MAINTENANCE.md`（坑 ×17 · 注入机制）。

⛔ **开源发布前**：`Get-ChildItem -Recurse -File | Select-String -Pattern OPENSOURCE-TEMP`，按标记处理（目前只有 `tts\docs\MAINTENANCE.md` §0 那一块）。
