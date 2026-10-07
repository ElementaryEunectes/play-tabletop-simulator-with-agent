# 通用工作流：用 DSH 在 Tabletop Simulator 里代玩任意桌游

> ⚠️ **脚本名以 `tts\SCRIPTS.md` 为准**：现役按频率分类；**已归档的一律在 `~\.dsh\archive\tts-legacy\`**（不在本仓库）。
> 本文提到的 `overview.ps1` / `init.ps1` / `resolve_*.ps1` / `dock*.ps1` 之类旧名都按归档看；`diff_safe.ps1` 已由 **`diff_hidden.ps1 -Game <游戏>`** 取代。
> 每回合怎么打看 `PLAY.md` · TTS 通用规则看 `TTS_RULES.md` · 上一局（游城拓荒）的文档在 `archive\`。

这份文档是从《明日方舟：游城拓荒》那一局里**踩了十几轮坑**之后总结出来的。
核心教训一句话：**不要用截图去反推坐标。** 游戏自己知道每个物件在哪，
截图是给人看的，机器读它既慢又错。

**外部调研见 [`PRIOR_ART.md`](PRIOR_ART.md)** —— 「AI 在 TTS 里打桌游」的网上先行研究。
三条与本工作流直接相关的结论：
1. **公开项目里这种实现是 0 个**；所有 TTS 自动化都走官方 **External Editor API**，
   本文档描述的做法与主流一致。
2. 学术基准（BALROG）与工程实践（Tablescope：一个博士团队花 20 个月做「照片 → 桌面状态」）
   都指向同一条：**结构化状态 > 像素状态**。即本文档第 0 节那张表。
3. **隐藏信息（手牌）在 TTS API 层拿不到** —— 它是会话状态、不落盘。
   换任何桌游都会撞上；标准解是**让玩家把隐藏牌放到桌面，读 `CustomDeck.FaceURL` 认牌**。

---

## 0. 一句话原则

> **什么时候读我**：动手之前扫一眼，用哪条方法别选错。

| 想做的事 | 该用的方法 | 绝对不要 |
|---|---|---|
| 知道某物在哪 | `getPosition`（Lua）或存档 JSON | 截图上量像素 |
| 知道板上某点在桌面哪 | 板子 `positionToWorld()` | 手工算比例 |
| 知道某卡是什么 | `CustomDeck.<id>.FaceURL` 的 40 位 hash → 本地图缓存 | 靠截图辨认 |
| 知道板子多大 | `getBounds()` / `getVisualBoundsNormalized()` | 假设尺寸 |
| 知道板面图案在哪 | 按**颜色**识别（LockBits），并且只作**交叉验证** | 肉眼读缩略图 |
| 把棋子放对位置 | 先算，再 `getPosition` 回读确认 | 放完就假定对了 |

---

## 1. 启动与连通（每个新会话）

每个新会话第一件事：跑一次 `ds.ps1 -Do ping`，确认**命令层活着**、并**看清它报的版本号** ——
版本号是"桥接有没有真的进去"的唯一凭据，**具体数值以 `ping` 实际返回为准**，本文档不再写死任何版本号/物件数/存档名。
载入哪个存档、桥接怎么装、`ping` 不回时怎么查 —— **完整流程见 [`BOOTSTRAP.md`](BOOTSTRAP.md) §1（冷启动四步）**。
玩家沟通、发消息等细节同见该文件。

---

## 2. 先建「物件索引」，别用 Lua 全扫描

> **什么时候读我**：需要"桌上有什么 / 某物在哪 / 容器里有什么"，或 `find:`/`count:` 这类批量命令不回复时。

**问题**：Lua `getObjects()` 只给顶层物件，袋子/牌堆里的东西拿不到；
而 `find:` / `count:` 这类批量命令在 400+ 物件时会 15–90 秒超时。

> ⚠️ **更正（2026-10-04）**：`find:` 从来不是"超时"。**凡是返回列表的命令都发不出回复**，
> 因为 TTS 的 `sendExternalMessage` 无法序列化嵌套表，而那一句没包 pcall，整个回复流程静默死掉。
> 现在已修（回复里的列表压成 JSON 字符串 + 包 pcall）。判别诀窍：**发一个不存在的命令**，
> 它一定回 `no handler`；**命令已知却完全不回 = 就是这个 bug**。

**做法**：直接解析自动存档，生成一张全量表。

```powershell
& powershell -NoProfile -File '<本仓库>\tts\obj_index.ps1'
# -> cache\obj_index.csv ：一行一个物件（行数以实际存档为准），
#    每行 guid/name/nick/x/y/z/sx/rotY/rotX/rotZ/gm/ss/url/depth/parent/src/pdfurl
#    （src = url 的来源字段；pdfurl = Custom_PDF 的完整 URL —— 规则书就是这么取到的，见 RULEBOOK.md）
```

关键实现要点（都是踩过的坑）：
- 用 `JavaScriptSerializer`（**提高 `MaxJsonLength`**）解析，不要用 `ConvertFrom-Json`
  （带大 Lua 的存档 JSON 会抛 ArgumentException）。
- 递归走 `ObjectStates` / `ContainedObjects` / `ChildObjects` / `States`。
- **袋子里物件在被取出前不会成为顶层物件**，所以也要把容器展开：
  ```powershell
  & powershell -NoProfile -File '<本仓库>\tts\bags_dump.ps1'
  # -> cache\bag_contents.txt ：每个容器 + 它的内容物（GUID/图片/计数）
  ```
- `ConvertFrom-Json` 出来是 PSCustomObject：**用 `$v.FaceURL`，不要用 `$v['FaceURL']`**。

**查东西**：直接对 CSV 用 grep/Import-Csv，比任何 Lua 命令都快。

---

## 2b. ⭐ 看全貌 + 定位「这东西到底在哪」

> **什么时候读我**：要判断"桌上都有什么"，或有个东西还没认出来、想知道它在哪。

**要回答「桌上都有什么、那个我还没认出来的东西在哪」，不要靠截图碰运气。**

### 2b.1 全貌图从哪来

| 来源 | 结论 |
|---|---|
| **存档缩略图 `TS_AutoSave*.png`** | ❌ **实测只有 256×256**。文件 ~150 KB 全是未压缩像素，别被大小骗了。**只能做「有没有东西被挪动」的粗检。** |
| **高分辨率俯视截图** | ✅ **正解**。一张就能看清全部编号、计数器数字、卡面。玩家给，或自己 `grab_window.ps1 -Handle <hwnd>` 抓（抓的是**当前相机**，要先把镜头拉到俯视全景）。 |
| 普通游戏内截图 | ⚠️ 只是当前视角，多半看不到全桌；一次 1–2k token，不如一张全貌图划算。 |

存成 `cache\table_overview.png`，后续分析都在这一张上做。

### 2b.2 把世界坐标烧到图上

```powershell
& powershell -NoProfile -File '<本仓库>\tts\overview.ps1' -Filter 'Token' -Labels
# -> cache\overview_annotated.png
#    世界坐标网格 + 地图板矩形 + 每个匹配物件的红点与 guid
```
`-Filter` 按 `name`/`nick` 子串过滤（不加 = 全部 1000+ 个物件全点一遍，会糊）。

**标定「世界 → 图素」**：俯视图是仿射的，**两个点对就够**
```
img_x = OffX + Scale * world_x
img_y = OffZ - Scale * world_z        # 图上 y 向下 = 世界 z 减小
```
取两个**在全貌图上看得见、且 `obj_index.csv` 里有坐标**的物件当锚点
（挑那种一眼能认出、坐标又不会被别人挪动的物件，例如计数器），代进去解 `Scale` / `OffX` / `OffZ`。
⚠️ **别用地图板的边框当锚点** —— 板子的可见图素常比 `getBounds()` 的碰撞盒大，
本局实测差近一成，拿它标定会把整张图缩错。

### 2b.3 定位任何一件东西的标准动作

1. `obj_index.ps1`（**先确认打印的存档 mtime 是新的**）
2. `overview.ps1 -Filter '<关键字>' -Labels` → 读 `cache\overview_annotated.png`
3. 找到目标 → **回读** `ds.ps1 -Do 'act:<guid>:getPosition'`
4. 图上认不出 → **裁图放大**：把世界坐标反投影成图素再裁

> **原则**：全貌图用来**发现和缩小范围**；精确坐标一律回读 `getPosition`。
> **图是给人看的，数字要问游戏要。**

### 2b.4 待标定项的收敛套路

"待标定"的东西（玩家版在哪、某个牌堆是哪种颜色、某条轨道的格子间距）**不是靠问，是靠图收敛**：

1. 先在全貌图上找**候选**（形状、大小、方位、和其它已知物的相对关系）
2. 用 `obj_index.csv` 按特征筛（`name` / `scale` / `nick` / 坐标区间）缩小到几个
3. **回读 `getPosition` 确认**，或**裁图直读**（牌面编号 / 卡面文字）
4. 一旦确认，把 guid + 坐标**写进本文档对应的"物件对照"节**，下次直接查

⚠️ **两条血泪教训**
- **别按"离某个参照点最近"来判身份**：本局我就是这么把两座移动城市的归属弄反，
  还错误地宣布"某玩家的城市放错了 25 格"。**正确做法是反投影成图素、裁图直读编号。**
- **别把"我按推算值摆的东西"当成验证** —— 那是循环验证，证明不了任何事。

---

## 3. 卡片/指示物识别：认 hash **+ CardID**，不认名字

> **什么时候读我**：要认某张牌/某个指示物是什么，或拼图卡片只知 hash 不知是哪一格时。

存档里卡片名字都是 `Card` / `CardCustom`，唯一身份是图片 URL。

- `CustomDeck.<CardID>.FaceURL`，取 URL 尾段的 **40 位十六进制 hash**。
- **同一个图在不同主机会有不同的域名**（`steamusercontent-a.akamaihd.net` vs
  `cloud-3.steamusercontent.com`）→ **匹配 hash，不要匹配整个 URL**。
- 本地图缓存在 `...\Mods\Images\<扁平化URL>.<ext>`。
  `tts\resolve_cards.ps1` 把存档卡片映射到本地文件，写出 `cache\card_resolved.csv`。

### 3.1 ⭐⭐ hash 不够：一张拼图可以装很多张牌

`CustomDeck` 的图可以是一张**拼图**，由 `NumWidth × NumHeight` 切成格子，
用 `CardID` 选格子：

```
CardID = deckId * 100 + 格号      # 格号从 0 起，从左到右、从上到下
```

⇒ **`NumWidth*NumHeight > 1` 时，hash 相同的若干张牌是【不同的牌】。**

**踩过的实例**：8 张企业板共用拼图 `480DBC07…`（`NumWidth=4, NumHeight=2`，deckId `625`）。
我只按 hash 判断，看到桌上 4 张板 hash 全同，就以为「4 张一样的牌」，
**然后凭记忆给它们贴了名字 —— 全错**（把 `CardID 62505` 的「约翰老妈」写成了「富森银行」，
而富森银行 `62503` 其实根本不在桌上，收在场外侧堆里）。

**规则**
1. **认牌 = `FaceURL` hash + `CardID`**（必要时再加 `NumWidth/NumHeight`）。
2. **拿不到 `CardID` 就不要猜名字** —— 直说「不知道」，或者把拼图按格裁开来看。
3. 查 `CardID`：**`tts\guidinfo.ps1 -Guid <g1>,<g2>`**（正则直接切存档文本）。

**⚠️ 不要用 `JavaScriptSerializer` 解析这些存档**：实测抛 `ArgumentException`
（递归/长度上限），而且**异常会把整份 JSON 打进 stderr**，token 成本极高。用正则截取。

**⚠️ `powershell -File x.ps1 -Guid a,b,c`** 会把 `a,b,c` 当作**一个字符串**传进来，
数组参数**不会**自动按逗号拆 —— 脚本里要自己 `-split ','`。
（同类陷阱：`f $arr[0] $arr[1]` 会把整个数组绑给第一个参数。）

**给卡片命名**：`tts\label.ps1` —— 你只填「第几号图 + 名字」，工具回填 hash。
> ⚠️ 我犯过一次大错：手打 48 个 hash 进 `card_names.csv`，全是编的。
> **永远不要让模型手抄 hash**，一定用工具从图里取。

---

> 地图板几何已迁至《游城拓荒》手册 `archive\NOMADCITY_FLOW.md` 的「附录A」（该局已终局）。

## 5. 读写物件：能做什么、做不到什么

> **什么时候读我**：要读写某物件的属性、或某个命令报 `no method` / 计数器屏幕不动时。

### 5.1 Lua 沙箱的能力边界（实测）

`sandbox` 里 **`load` / `loadstring` / `eval` / `setUI` / `io` / `loadfile` 全是 nil**。
所以命令层必须是**显式白名单 + 手写分支**，不能动态构造调用。

可用且已验证的 verb（在 `tts\lua\dsh_global.lua` 的 `verbs` 表里）：
`getPosition/setPosition`、`getRotation/setRotation`、`getScale/setScale`、
`getBounds/getBoundsNormalized/getVisualBoundsNormalized`、
`getGMNotes/setGMNotes`、`getName/setName`、`getDescription/setDescription`、
`getColorTint/setColorTint`、`getLock/setLock`、`getValue/setValue`、
`getQuantity`、`flip`、`shuffle`、`deal`、`setState`、`getStates`、
`positionToLocal/positionToWorld`、`getScreenPosition`。

**不存在的**：`setLuaScriptState`（`script_state` 是**成员变量**，直接赋值，
不是方法）。**且成员变量 verb 必须在「方法查找」之前处理**，否则会误报
`object has no method ...`——这个坑让我绕了两轮。

### 5.2 计数器的两种机制（别搞混）

| 机制 | 谁在用 | 读 | 写 |
|---|---|---|---|
| `GMNotes` | 资源计数器类（12 个资源牌） | `getGMNotes` | `setGMNotes` |
| `LuaScriptState` | MrStump 的 Universal Counter Token | `getScriptState` | `setScriptState`（值必须是合法 JSON，如 `{"saved_count":12}`）|

### 5.3 移动物件的正确写法

```lua
-- ✅ 直接位置参数
o.setPosition({ x, y, z })
-- ❌ 通过通用的 fn(o, {x=..,y=..,z=..}) 会报
--    "cannot convert a userdata to a clr type UnityEngine.Vector3"
```
所以 `ds.ps1` 里专门有 `move:` / `rotate:` 两个动词走**专用 handler**，
不要用通用 `act:` 去调 `setPosition`。

### 5.4 棋子「落在板子上」的判据

放完**一定回读**：`getPosition`。
板面高度 = 板中心 y + 板厚/2。棋子 y 明显高于它 = 在板上；接近桌面 y ≈ 2 = 掉到桌子上了。
> 我曾把棋子放到板外，它掉到桌上（y 从 2.6 变 1.9），这就是「放歪了」的信号。

---

## 6. 截图与窗口（只在必要时用）

> **什么时候读我**：确实必须截图（全貌图、给玩家看）时；**平时状态一律用 Lua 读，别截图**。

**省 token 纪律**：状态一律用 Lua 读，**不要用截图**。

必须截图时：

```powershell
# 先把 TTS 抢到前台（SetForegroundWindow 直接调用会返回 False）
& powershell -NoProfile -File 'tts\alt_activate.ps1'
#   -> 原理：先 SendInput 发一次 ALT 轻敲，再 SetForegroundWindow
# 再按句柄抓窗口
& powershell -NoProfile -File 'tts\grab_window.ps1' -Handle <hwnd>
```

坑：
- `grab_window.ps1 -TitleMatch 'Tabletop Simulator'` 会**抓到浏览器**——
  因为 DSH Web GUI 页面的标题里也含这串字。**始终用 `-Handle`。**
- 拿句柄：枚举可见窗口（EnumWindows + GetWindowText + GetWindowRect）找标题精确匹配的那个。
- `PrintWindow` 对 Unity 通常失败 → 脚本自动回退到 `ScreenBitBlt`，
  这就要求 **TTS 必须在前台**，否则抓到的是压在它上面的窗口。
- 抓完先看字节数：几百字节 = 全黑/失败，几 MB = 成功。

---

## 7. 改游戏内 Lua 的安全流程（每次都要走）

> **什么时候读我**：要改 `dsh_global.lua` / 重装桥接 / 修 notebook 页 id 时，**照抄，别跳步**。

```powershell
# 1) 语法校验（必跑！曾抓到 here-string 里混进字面量 `r`n 的致命 bug）
node tts\validate_lua.js tts\lua\dsh_global.lua
# 2) 从「最新自动存档」重建存档槽（装 Lua + 给每个 notebook 页唯一 id）
& powershell -NoProfile -File 'tts\install_save2.ps1'      # 需要 danger-full-access
# 3) 让玩家 Menu → Load → <上一步写出的那个槽位>（槽位名/存档名以本次实际安装结果为准）
```

- `validate_lua.js` 是 luaparse 0.3.1（依赖在 `cache\luaparse`）。
- **PowerShell here-string 不转义反引号**：单引号 here-string 里写 `` `r`n `` 会原样进 Lua。
- notebook 页 **`id` 必须唯一**，否则 `getNotebookTabs()` 顺序不稳定、写入永远写偏。
- 写盘后 `ds.ps1 -Do ping` 的 `loads=` 会变，是判断玩家是否重载过的依据。
- 存档目录在 workspace 之外 → 写盘需要单次提权 `danger-full-access`（预期行为）。

---

## 8. 跟玩家协作的正确姿势（我这次做错的）

> **什么时候读我**：要请玩家做动作 / 要向玩家确认某件事之前。

1. **尽早要一个锚点。** 需要「图上某点 ↔ 桌面某点」的对应时，
   请玩家用鼠标把任意一个棋子放到那个位置，比任何图像分析都准、都快。
   我拖了十几轮才想到这一步，纯属浪费。
2. **不要连续试错放置。** 每放错一次就动一次玩家的棋盘。
   先用公式算好、用两个独立锚点验完，再一次性放。
3. **不确定时明说。** 「我肉眼读图不可靠，请你确认一眼」比继续猜要好。
4. **别用截图判断棋子落在哪个格子上**——这正是我反复失败的环节。
   要么用坐标验证，要么让玩家看一眼。

---

## 9. 一次标准开局的工作流（可直接套用到别的桌游）

> **什么时候读我**：接手一个**没见过的桌游/模组**，要按顺序把桌面认下来时。

```
 1. ping / tabread                        → 确认连通 + 读玩家留言
 2. obj_index.ps1 + bags_dump.ps1         → 全量物件表（本地 grep，不再用 Lua 扫）
 3. 找板子：getPosition/getRotation/getBounds → 记下中心、rotY、尺寸
 4. ⭐ 坐标初始化：请玩家做一次校准动作（做法已随 §4 迁走：见本局手册 `_FLOW.md` 的「附录A」）
      玩家把棋子拖到地图上某个明确参照点 → getPosition
      => 一次拿到「坐标锚点」+「位移矢量」，之后不再问坐标
 5. （可选）star_find.ps1                 → 交叉验证板面标记位置（只用来验证，不用来推方向）
 6. 算目标坐标 → move: → getPosition 回读   → 逐个确认落点
 7. 写状态：setGMNotes / setScriptState    → 回读确认
 8. say.ps1 汇报 + 请玩家确认               → 只问一次，别反复
```

### ⚠️ 写入前的强制 sanity check（血的教训）

我曾把 `$OZ - $SZ*$py` 写成让 PowerShell 把 `-SZ` 当参数、`$py` 当**指数**，
算出 **2.8 × 10²¹** 的坐标，把一个模型移过去后**被物理引擎销毁**。

**规矩：任何 `move:` 之前，先打印目标坐标并检查范围。**

```powershell
# $half = 本局板子半宽 —— 用 act:<boardGuid>:getBounds 当场读，别照抄旧数字
if ([math]::Abs($x) -gt $half -or [math]::Abs($z) -gt $half) {
    Write-Host "REFUSED: ($x, $z) off the board"; exit 1
}
```

配套的 PowerShell 陷阱（**每条都实际咬过我**）：

| 写法 | 后果 |
|---|---|
| `$a - $b * $c` 在表达式/参数位 | `-b` 被当成**参数名**，`$c` 变指数 → 天文数字 |
| `[math]::Round($a - $b*$c, 3)` | 整个表达式求值失败或算错 |
| `f $arr[0] $arr[1]` | 整个**数组**绑给第一个参数 → "cannot convert System.Object[] to System.Double" |
| `$g` 之类单字母变量 + `-G` 参数 | 撞名，类型错乱 |
| here-string 里的 `` `r`n `` | 原样写进 Lua → 语法错误 |
| **含中文的 `.ps1` 存成无 BOM 的 UTF-8** | ⚠️ **`powershell -File` 按 ANSI 读脚本** → 中文全变乱码 → 报一堆 `Missing closing ')' in expression`。**含中文的 .ps1 必须带 BOM**：`[System.IO.File]::WriteAllText($p,$t,(New-Object System.Text.UTF8Encoding($true)))` |
| 双引号字符串里再写 `"` | 字符串提前结束 → 解析失败（用 `「」` 或 `` `" ``） |
| 双引号字符串里的 `` `t ``（想写路径 `tts\...`） | 反引号是转义符，被吃掉 → 写成 `` `` `` 或改用单引号 |

**一律：先取成 typed 标量、显式加括号、写盘前打印验证。**
**含中文的脚本写完先 `powershell -File` 空跑一次**，别等到真用时才发现是乱码。

> **另一类"陷阱"不在语法在数据**：本 mod 有 **5 个 `HandTrigger`** —— 四个在座位排（z≈−115），
> 一个离群的在 z=+114。**按 x 排序会把离群那个插进座位中间，让所有玩家归属整体错位。**
> ⇒ 排序前必须先按 z 过滤出座位排。**凡是"按某个坐标排序来分配身份"，先确认没有离群样本。**

---

## 10. 工具清单（都在 `tts\`）

> **什么时候读我**：想知道"这个脚本是干什么的 / 有没有现成工具"时（先查表再写新脚本）。

| 脚本 | 作用 |
|---|---|
| `ds.ps1` | **唯一通信入口**，一行输出。`ping/tabread/tabwrite/notepush/act/geom/move/rotate/find` |
| `say.ps1` | 往 TTS 对话频道发消息（滚动窗口，自动归档旧正文） |
| `obj_index.ps1` | 自动存档 → `cache\obj_index.csv` 全量物件表 |
| `bags_dump.ps1` | 展开所有容器内容 → `cache\bag_contents.txt` |
| `star_find.ps1` | 按颜色识别板面标记（LockBits，秒级） |
| `dock2.ps1` | 十字星 → 停靠点换算 + 位移矢量探针（含写入前 sanity check） |
| `resolve_cards.ps1` / `card_index.ps1` | 卡片 → 本地图缓存映射 |
| `label.ps1` | 给图命名（只填序号+名字，hash 由工具回填） |
| `grab_window.ps1` | 按句柄抓 TTS 窗口（`-Handle <hwnd>`） |
| `alt_activate.ps1` | 抢 TTS 前台（先 ALT 轻敲） |
| `install_save2.ps1` | 重建存档（装 Lua + 修 notebook id） |
| `validate_lua.js` | Lua 语法校验，写盘前必跑 |

**不要用**：`daemon\`（已废弃）、`set_lua_live.ps1`（TTS 不接受，还会打哑运行中的脚本）、
`archive\tts-old\fix_tabs.ps1`、`repair_slot5.ps1`（会破坏 tab id）。
