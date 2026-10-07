# TTS_RULES.md —— Tabletop Simulator 代玩规则（**做 TTS 工作时读一次**）

> **什么时候读我**：任务是在 TTS 里替人打桌游（任何一款）时。
> **别的项目不要读我** —— 平台纪律在 `~/.dsh\AGENTS.md`（自动注入）。
> 每款游戏的规则/坐标/状态在 `tts\docs\`（索引：`README.md`；**每局随身卡**：`PLAY.md`）。

## 一、跟人怎么配合

- **玩家（人类）= P1**：只做两件事 —— ① 自己的决策 ② **点「结束回合」按钮**。**我 = 其余席位，全部棋子操作归我。**
- ⭐ **决策归玩家，操作归我**：玩家的选择必须把「**选项 ＋ 代价**」摆出来等他点，**绝不替他拍**；我自己的席位我自己决定。
- ⭐ **玩家每次宣告动作 = 给我一次「响应窗口」**（打行动牌 / 改骰 / 逼重掷 / 防守技）⇒ **必须表态**（"我出牌 / 我不出牌"），
  **不能当成他已经定型就直接结算**。
- 沟通三条：**DSH Web GUI 聊天框** · **TTS 笔记本对话频道**（`ds.ps1 -Do tabread`）· 桌上实物/图。**都要看。**
- ⛔ **隐藏信息双向纪律**：① **不读**对手隐藏区（手牌/盖放/牌堆顶），**也不做位置推断**；
  ② **我自己的隐藏信息也不说**（手里有什么牌 / 盖放了什么 / 下一步打算）。只报**已公开的事实**（移动 · 落点 · 计数 · 牌堆张数 · **已翻开的牌**）。
  看桌面变化一律走 **`diff_hidden.ps1 -Game <游戏>`**（按 `cache\hidden_zones.csv` 折叠隐藏区，从源头掐掉"看到了就顺手对上"）。
- ⭐ **对手翻出的公开牌必须主动读**（事件牌/结算牌）：不读就无法核对计数、也预判不了局势。**别等他提醒。**

## 二、工具地图（全在 `tts\`；死代码在 `archive\tts-legacy\`）

| 场景 | 用什么 |
|---|---|
| 跟 TTS 说话 | **`ds.ps1 -Do '<动词>'`** —— `ping` · `tabread` · `getState:<guid>` · `setState:<guid>:<json>` · `setCount:<guid>:<N>` · `call:<guid>:<fn>` · `act:<guid>:<verb>` · `move:<g>:<x>:<y>:<z>` · `rotate:` · `flip:<g>` · `draw:<deck>:<n>:<x>:<y>:<z>[:1]` · `find:` · `all:<n>` · `read:<g>` · `probe:<g>` |
| 原始通道 / 底座 | `ttsx.ps1 -Cmd '<json>'`（只回 `customMessage`）· `ttslib.ps1`（**dot-source，别 spawn**） |
| 多命令一次跑 | `dsbatch.ps1 -Commands 'a;;b'`（⚠️ 两层子进程会被沙箱掐网络 ⇒ 优先 `ds.ps1` 逐条） |
| 看桌面变化 | `live_index.ps1`（实时快照 CSV）· `diff_index.ps1 [-Snapshot]` · **`diff_hidden.ps1 -Game <游戏>`（对外一律用这个）** |
| 认牌 / 查牌 | `card.ps1 -Q '<名字>'`（卡库 `cache\dicethrone_cards.md`）· `guidinfo.ps1 -Guid a,b`（CardID）· `obj_index.ps1`（存档索引，滞后 ~5 min） |
| 发消息 | `say.ps1 -MessageFile <utf8.txt>`（**中文走文件**） |
| 叫醒 / 判活 | `front_watch.ps1` → `cache\front.txt`（`TURN=Pn`）· `channel_watch.ps1` → `cache\chan.txt`（`NEW`）→ 配 **file 哨兵** |
| 读"轮到谁" | `read_turn.ps1`（采样横幅色块）；TTS 不在前台 = `NOTFOREGROUND`，**不给假数据** |
| 换局 / 冷启动 | `BOOTSTRAP.md` ＋ `bootstrap.ps1` · `install_save2.ps1`（写存档唯一通道）· `crop_zoom.ps1`（裁图读牌面） |
| 改完脚本 | `check_ps1.ps1`（补 BOM ＋ 真解析器校验全部 `.ps1`）· `validate_lua.js`（改 Lua 前跑，并同时改 `DSH_VERSION`） |

## 三、一回合怎么走

1. 读**该局自己的文档链**：`tts\docs\CURRENT.md`（在玩哪款）→ `tts\docs\<游戏>_STATE.md`（**唯一真源**：比分/资源/待办）
   → `tts\docs\PLAY.md`（**每局随身卡**：本局控制台动词 ＋ 每回合步骤）。
2. **核对盘面**：一条 `status` 类命令拿实测值（HP/CP/状态/物件数）——别靠记忆。
3. **该我走**：按 STATE 待办 ＋ `<游戏>_FLOW.md` 的技能表，**一条命令一个阶段**。
4. 摆玩家的选项；我自己的行动直接执行。
5. 写回 STATE（**只改"当前"块与待办**）→ 报一行公开事实 → **等哨兵叫醒**（不轮询）。

## 四、「结束回合」按钮（已定案，别再试）

- ✅ 它就是右上角那块「**Player N**」横幅本身（悬停弹出"点击结束回合"）。
- ⛔ **我点不了**：普通点击 / `-Absolute` / 绿星三种都试过全无效（TTS 不吃合成输入）。**永远由玩家点。**
- ✅ **自动叫醒**：`front_watch.ps1` 后台把"前台状态 ＋ `TURN=Pn`"写进 `cache\front.txt` → file 哨兵 pattern `TURN=P<我的席位>`
  ⇒ 玩家一点完就自动叫醒我。⚠️ sentinel 的 `command` 探测跑在只读沙箱（`Add-Type` 必崩）⇒ **只能 file 探测 ＋ 外部写文件**。
- ⚠️ TTS 不在前台时 `front.txt` 只剩 `OTHER/TTSFRONT`（读不出 TURN）⇒ **轮次要靠 STATE ＋ 盘面计数交叉判断**，别只看它。

## 五、⚠️ TTS 特有的坑（都付过代价）

- **`roll.ps1 -Tray <seat>` 默认会先掷骰再读点数**（源码 `if (-not $NoRoll) { act:<guid>:roll }`）⇒
  **只看当前骰面必须加 `-NoRoll`**；不带就是"重新掷这个托盘"。我把它当"读"用过，把玩家的实际投掷反复重掷，**玩家当场抓到**。
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
- 🕰️ 上一局（游城拓荒）留下的**跨游戏通用教训**已归档在 `tts\docs\archive\NOMADCITY_FLOW.md §18.10`（要重开那类游戏时看）。

## 六、换局 / 新游戏

- **冷启动 / 换局 / 换模组**：照 `tts\docs\BOOTSTRAP.md` 走（三种情形 ＋ 共同核心四步）；`ds.ps1 -Do ping` 是任何情形的第一步。
- **guid 全变** ⇒ 识别一律靠 **hash ＋ nick ＋ scale ＋ 坐标关系**，**绝不用记住的 guid**；上一局的坐标/常量一律作废
  （资源点上放什么常常是开局随机）。
- 换局后：改 `tts\docs\CURRENT.md`，新建 `<游戏>_STATE.md` / `<游戏>_FLOW.md`，卡库/规则库按需重建。
