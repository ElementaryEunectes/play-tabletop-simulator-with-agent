# tts\SCRIPTS.md —— `tts\*.ps1` 清单（**找脚本 / 清理时读我**）

> **什么时候读我**：想知道"这个脚本能不能动""有没有现成工具"时。
> 规则：**根目录只放现役工具**；死的/一次性的/实验性的在 **`~\.dsh\archive\tts-legacy\`**（33 个旧 `.ps1`，各自带 `README.md`）。
> ⚠️ 2026-10-08 更正：这个归档目录**不在本仓库里**（项目从 `~/.dsh` 迁出时没搬它），别再按 `..\archive\tts-legacy\` 去找。
> **改任何 `.ps1` 之后必须跑 `check_ps1.ps1`**（补 BOM ＋ 真解析器校验全部脚本）。

## ⭐ 核心（每局都在用）

| 脚本 | 干什么 |
|---|---|
| **`play.ps1`** | **本局控制台**（骰铸专用）：`status` / `income` / `roll` / `attack` / `defense` / `say` —— 一条命令一个阶段。**别 read 它的本体**（~10k token） |
| **`roll.ps1`** | 掷/读骰面：`-Tray moon\|scar` —— **必须明说意图**：`-Roll` 才掷、`-NoRoll` 只读；**裸调用 `exit 2`（不接触 TTS）** |
| **`ds.ps1`** | **跟 TTS 说话的高层入口**：`-Do 'ping / tabread / getState:<g> / setCount:<g>:<n> / act:<g>:<verb> / move:… / draw:… / all:<n> / read:<g>'` |
| `dsbatch.ps1` | 一条进程跑多条 `ds.ps1` 命令（`-Commands 'a;;b'`）；⚠️ 两层子进程会被沙箱掐网络，优先 `ds.ps1` 逐条 |
| `ttsx.ps1` · `ttslib.ps1` | 原始通道（只回 `customMessage`）＋ **唯一的 TCP 传输层**（`ttslib` **dot-source，别 spawn**） |
| `say.ps1` | 往笔记本对话频道发一条（**中文走 `-MessageFile`**） |
| `live_index.ps1` · `diff_index.ps1` | 整桌**实时**快照（CSV）· 差异（`-Snapshot` 冻结基线） |
| **`diff_hidden.ps1`** | **带隐藏区遮蔽的 diff —— 对外显示一律用它**（规则在 `cache\hidden_zones.csv`） |
| `card.ps1` | 查卡面文本库 `cache\dicethrone_cards.md`（`-Q '<名字>'`） |
| `front_watch.ps1` | 后台：写 `cache\front.txt`（前台状态 ＋ `TURN=Pn`）→ 配 file 哨兵叫醒 |
| `channel_watch.ps1` | 后台：写 `cache\chan.txt`（笔记本尾部变化 → `NEW`）→ 配 file 哨兵 |
| `check_ps1.ps1` | **改完 `.ps1` 必跑**：补 BOM ＋ 真解析器校验 |

## 🔧 常用（按需）

| 脚本 | 干什么 |
|---|---|
| `obj_index.ps1` | **存档**侧全量物件索引 → `cache\obj_index.csv`（含 url hash / 容器关系 / GMNotes；**滞后 ~5 分钟**） |
| `guidinfo.ps1` | 给定 guid → 从存档里切出 CardID / deck / 位置等身份字段（**认牌用**） |
| `bags_dump.ps1` · `bag_list.ps1` | 展开容器（牌堆/袋）内容 → `cache\bag_contents.txt` |
| `bootstrap.ps1` | **换局/新存档**时重新认一遍关键物件（guid 全变的场合） |
| `install_save2.ps1` | **写存档的唯一通道**（把 `lua\dsh_global.lua` 灌进存档 ＋ 修 notebook tab id；需一次提权） |
| `crop_zoom.ps1` | 裁图 + 放大转真 PNG（**读卡面/查图用**；`Mods\Images` 里扩展名常与真实格式不符） |
| `read_turn.ps1` | 采样 mod 横幅色块 → `PLAYER=n`（TTS 不在前台时报 `NOTFOREGROUND`，**不给假数据**） |

## 💤 休眠但别删（只在特定情形才用 —— 删了会踩坑）

| 脚本 | 什么时候才需要 |
|---|---|
| `card_index.ps1` · `index_images.ps1` | 要把**卡片映射到本地图缓存**时（建卡库、认新牌面）—— 现在卡库已建好，平时不用 |
| `grab_window.ps1` | 抓 TTS 窗口像素（**Unity 下 `PrintWindow` 无效，靠 BitBlt**）；被 `read_turn.ps1` 引用；"没有 Lua 通道、只能看画面"时的兜底 |
| `tts_click.ps1` | 合成鼠标输入。⚠️ **已定案：合成点击点不到 mod 的「结束回合」按钮** ⇒ 基本没用；但 `front_watch.ps1` 默认参数引用它，**动它要连 `front_watch` 一起改** |
| `tts_api.ps1` | TTS **External Editor API（39999）** 原始客户端；协议表在它文件头。`ds.ps1`/`ttsx.ps1`（40000 消息通道）是主路，这个是退路 |
| `validate_lua.js` | **改 `lua\dsh_global.lua` 之前**必跑（并同时改 `DSH_VERSION`） |

## 🧪 测试（**不开 TTS 也能跑**）

| 脚本 | 干什么 |
|---|---|
| `tests\test_diff_index.ps1` | `diff_index.ps1` 的**离线自测**：`fake_live_index.ps1` 冒充 `live_index.ps1`，`fixtures\*.csv` 是合成数据 ⇒ 六类变化各 1、`-Snapshot` 写基线、相同快照必须安静 |
| `tests\test_param_backfill.ps1` | **每个 `''` 默认值都必须被回填或判空** —— 就是那次"5 个脚本能解析、一跑却写空路径"的 bug 类 |
| `tests\fake_live_index.ps1` | 上面用到的桩（只认 `-Out`） |
| `tests\fixtures\` | 合成的前后快照 CSV（**不是真实存档**） |

跑法：`powershell -NoProfile -ExecutionPolicy Bypass -File tts\tests\test_diff_index.ps1`（`exit 0` = 过）。
⚠️ `check_ps1.ps1` 现在是**递归**的 ⇒ 测试自身也会被补 BOM ＋ 真解析器校验。
⚠️ **校验器要有阳性对照**：`test_param_backfill.ps1` 第一版因为正则锚在行首而**完全看不见**单行 `param([string]$X = '')`，
  故意造一个坏脚本才试出来（`HANDOFF.md` §6.8）——改这个测试时必须重跑那个对照。

## 目录

```
tts\
├── *.ps1            现役脚本（本文件就是它的清单）
├── validate_lua.js  改 Lua 前的校验器
├── lua\             dsh_global.lua（桥接本体，install_save2.ps1 依赖，别动）· dsh_panel.lua
└── docs\            所有文档（索引 docs\README.md；TTS 通用规则 docs\TTS_RULES.md；每局随身卡 docs\PLAY.md）
```

⚠️ **跨脚本引用**（改名前先看这里）：`bootstrap → ds/obj_index/live_index` · `diff_index → live_index` ·
`live_index → ds` · `read_turn → grab_window/tts_click` · `front_watch → read_turn（＋ tts_click 参数）` ·
`channel_watch/ttsx/roll → ttslib` · `play → ttslib/say` · `install_save2 → lua\dsh_global.lua`。
