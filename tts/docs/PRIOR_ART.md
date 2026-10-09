# 先行研究：让 AI 在 Tabletop Simulator 里打桌游

> **什么时候读我**：想查先例、或怀疑"这件事别人做过没有"的时候。**本文冻结 —— 别重搜、别重写**（可搬/不可搬结论都在 §7.4 与 §8.3）。

**调研日期**：2026-10-04
**调研动机**：本项目的架构（外部进程 + 游戏内 Lua RPC 层 + 代打三个座位）是否是正路？
网上有没有现成方案、有没有别人踩过的坑可以抄？

---

## 0. 结论摘要（先看这五条）

> ⚠️ **2026-10-08 追加调研见 §7**：下面五条**仍然成立**（依然没有"AI 当玩家打完整一局"的公开实现），
> 但 **plumbing 层出现了开源方案**（`tts-toolkit` 的 hub/MCP 扇出），且新增了 agent 框架与两篇相关论文。

1. **公开项目里，「AI 当玩家在 TTS 里打完整一局桌游」的实现 = 0 个。**
   搜遍 GitHub、Steam 社区、arXiv，没有找到。我们做的事在这个生态里**是空白**。
2. **所有 TTS 自动化都走同一条路**：官方 **External Editor API**（TTS 监听 `39999`，
   编辑器监听 `39998`）。tts-editor（Node/TS）、tts-external-api（Rust）两个独立实现都是这个协议，
   **没有人绕过它**。→ 我们的直连 + Lua RPC 路线是主流正解，不是野路子。
3. **现有的「LLM × TTS」项目只做规则问答，不做棋子操作。** 最有代表性的
   `TabletopSimulatorCompanion` 是「TTS 内聊天提问 → Python + RAG 查规则书 → 回话」，
   真正的操作仍然靠人。
4. **隐藏信息（手牌）在 TTS API 层拿不到 —— 这很可能就是没人做出「AI 当玩家」的技术根因。**
   手牌是**会话状态**、不落盘（`HandTrigger` 在存档里是空容器）。所有被检索到的项目都在
   完全信息或无隐藏信息的场景里工作。我们撞上的「③ 弃手牌做不了」不是配置问题，是领域空白。
5. **行业共性痛点 = 长文档 AI 不读、状态读取靠猜。** 这正好解释了本项目为什么要写
   **按小节索引的 HANDOFF** 和 **一律用 Lua 读状态、不用截图反推**。

---

## 1. 直接相关：TTS 上的 AI 项目

| 项目 | 类型 | 关键事实 |
|---|---|---|
| [TabletopSimulatorCompanion](https://github.com/libin7099901/TabletopSimulatorCompanion) | LLM 规则问答 | 目前唯一完整的「LLM × TTS」项目（Python + Lua Mod，v0.3.4，2025-06） |
| [cloudwu/cardocr](https://github.com/cloudwu/cardocr) | 卡牌 OCR | 云风写的桌游卡牌识别：`ollama` + `qwen3-vl` 提文字与图标；**测试图取自 TTS 创意工坊 mod** |
| [shino-miniatures：BOT pour TTS](https://www.shino-miniatures.fr/web/projets-bot-pour-tabletop-simulator.html) | 规则 BOT 实践日志 | 2026-01 起用 ChatGPT 给《Confrontation》做 BOT；作者抱怨见下 |
| [rolandostar/tts-editor](https://github.com/rolandostar/tts-editor) | 协议参考实现（Node/TS） | 完整实现 External Editor API 全部 4 发 / 8 收消息类型，附假 TTS 后端便于单测 |
| [LucasOe/tts-external-api](https://github.com/LucasOe/tts-external-api) | 协议参考实现（Rust） | 同上；文档里明确「API 结构体绑定 `39999` 监听」 |
| [Steam：Can I script an AI?](https://steamcommunity.com/app/286160/discussions/0/6400272499512230488) | 社区提问 | 社区共识 = 没有现成的，自己写（正文抓取被 Steam 拦截，仅得标题） |
| [Steam：How to play game with AI??](https://steamcommunity.com/app/286160/discussions/0/1319962417043058970) | 社区提问 | 同上 |
| [Zavian/Tabletop-Simulator-Scripts](https://github.com/Zavian/Tabletop-Simulator-Scripts) | Lua 脚本库 | 纯自动化脚本（不是 AI），可作为物件操作写法参考 |

### 1.1 `TabletopSimulatorCompanion` —— 值得细看的一个
- **架构**：TTS 内 Lua Mod（`tc_mod.lua`）+ 本地 Flask 服务端（`TTSAssistantServer`）。
- **交互**：玩家在 TTS 里打 `@tc 你的问题`，服务端 RAG 后把答案显示给对应玩家。
- **技术栈**：Langchain + FAISS + Sentence-Transformers；LLM 可换 Gemini / Ollama / OpenAI。
- **值得抄的两点**：
  1. **它的核心价值是「把规则书变成可检索索引」**，不是「AI 会玩」。→ 印证我们「按小节索引文档」的做法。
  2. **它教了怎么从 TTS 数据里拿规则书 URL**：右键桌面的 PDF 物件 → 自定义 → 能看到 URL；
     或直接在存档/工坊 JSON 里找 `Custom_PDF` 的 `PDFUrl` / `FileURL` 字段。
     → **和本项目读 `CustomDeck.FaceURL` 是同一招**：TTS 存档是结构化元数据宝库。
- **它没做的**：读棋盘状态、移动棋子、代打。也没有隐藏信息处理。

### 1.2 `cardocr` —— 同行的视觉路线（我们的对照面）
- 做法：对**卡面图片**调 `ollama` 跑 `qwen3-vl`，抽文本 + 图标语义（能把 `[GEM]`、`[ALLY]`
  这类图标翻译成语义标签）。
- **成本结构完全不同**：一张卡一次 VLM 推理（慢、有概率错、要模型权重）。
- **我们的做法**：直接读 `CustomDeck.<CardID>.FaceURL` 的 **40 位哈希**（免费、确定、可去重）。
- **结论**：**TTS 里优先读 `FaceURL`，视觉只在牌面朝下 / 隐藏时才需要。**
  这条差异是本项目相对 cardocr 的核心优势，别丢掉。
- 附注：它的测试样本就是 TTS 工坊 mod 里的卡图 —— 说明**从 TTS 提取卡面素材**这件事
  大家做法一致（我们读存档，他读工坊文件）。

### 1.3 Shino 的 BOT 日志 —— 唯一找到的「LLM 在 TTS 里做规则执行」的一手实践
作者的抱怨原话（法语，2026-01-22）：

> 「目前进展还不错，虽然要**把所有东西都给 AI 讲清楚相当费劲** —— 它明明手上有文件
> （规则、档案、技能……），却**似乎并不总是去读、去遵守**。」

- 这正是我们这边反复出现的现象：**长文档给了 AI，AI 不一定会用。**
- 唯一有效的对策：**不要一次性喂全文，要给索引 + 按需切片**（= 本项目 HANDOFF 的小节索引）。
- 另一个观察：即使有全部规则文本，**规则执行的正确性仍然要靠人兜底**（他也在人工核对）。

### 1.4 社区现状：问的人多，做的人没有
Steam 社区两个高热度提问（「Can I script an AI?」「How to play game with AI??」）
都只拿到「自己写脚本」类回答。**没有任何官方 AI 对手，也没有第三方成品。**

---

## 2. 相邻领域：不是 TTS，但方法论可搬

| 项目 | 是什么 | 可搬的东西 |
|---|---|---|
| [PyTAG / TAG Framework](https://ieeexplore.ieee.org/document/10333223) · [论文 PDF](https://tabletopgames.ai/assets/pdf/balla2023pytag.pdf) | 把桌游封装成 RL 环境的框架 | 状态表示要**结构化**、动作空间要**离散可枚举** —— 我们 `act:` 动词白名单正是这个思路 |
| [RainbowArena](https://dl.acm.org/doi/abs/10.5555/3709347.3743963) | RL + LLM 双路线的多智能体桌游工具包 | 多座位代打（本项目要同时演 P2/P3/P4）在文献里是独立课题 |
| [BALROG](https://huggingface.co/papers/2411.13543) | LLM/VLM 当游戏 agent 的基准 | 明确对比「文本状态」vs「像素状态」两种输入 —— 文本状态显著更可靠 |
| [Seeing Without Understanding (ICML 2026)](https://icml.cc/virtual/2026/poster/61694) | 拆解 VLM 打游戏的「感知 / 推理 / 模拟」三段 | **看着对 ≠ 推理对**。截图上「牌在那儿」不代表我理解对了局面 |
| [Tablescope（FFG / TU Graz，2022–2024）](https://projekte.ffg.at/projekt/6c98433e-f36b-1410-85f8-00d3c07d99bb) | 用 CV 把**真实桌面**照片变成游戏状态 | 说明了视觉路线的真实成本：语义分割 + one-shot learning + 合成图增强，20 个月项目 |
| [Tabletop Simulator Docs MCP](https://www.pulsemcp.com/servers/doc2mcp-tabletopsimulator) | 把 TTS 官方文档做成 MCP server | 只提供文档查询，不提供操作 |

**读法**：`Tablescope` 花了 20 个月 + 一个博士团队做「从照片认桌面」。
**TTS 里我们不需要做这件事** —— `getPosition` / 存档 JSON 已经把答案给了。
**任何「截图反推坐标」的冲动都应该被这条压下去。**

---

## 3. 官方 API 事实（[External Editor API 文档](https://api.tabletopsimulator.com/externaleditorapi/)）

### 3.1 端口方向
> 「编辑器监听 `39998`；TTS 监听 `39999`。」
>
> - **TTS → 编辑器**（我们收）：`39998`
> - **编辑器 → TTS**（我们发）：`39999`

### 3.2 messageID 全表（⚠️ 更正本项目旧笔记的一处错误）

| ID | 方向 | 含义 |
|---|---|---|
| `0` | 收 | Pushing New Object（右键开脚本编辑器时推对象信息） |
| `1` | 收 | **Loading a New Game / Get Lua Scripts 的回包**（全量 Lua + UI XML） |
| `2` | 收 / **发** | 收：print 输出；**发：CustomMessage → 游戏内 `onExternalMessage`** |
| `3` | 收 / **发** | 收：Lua error；**发：Execute Lua Code**（`guid` + `script`） |
| `4` | **收** | **`sendExternalMessage` 的回包（本项目唯一的读取通道）** |
| `5` | 收 | **Execute Lua Code 的返回值**（代码 `return` 什么就回什么） |
| `6` | 收 | Game Saved |
| `7` | 收 | Object Created（带新建对象 guid） |

**更正**：本项目 `HANDOFF.md` 旧文写「`5`（载入）」是**错的** —— 载入是 `1`，`5` 是
**ExecuteLua 的返回值**。过滤行为（只认 `messageID 4`）一直是对的，只是标签标错了。

**顺带一条**：`messageID 5` 能直接拿返回值，说明**官方本来就有「执行 Lua 并取回结果」的通道**，
不必像我早期那样用 `error("VALUE="..x)` 硬凑。但我们的 `messageID 4` 通道已经稳定，不必改。

### 3.3 一个容易忽略的硬前提
> 「要对某个物件执行 Lua，**该物件必须已经在 TTS 里关联了脚本**。否则报
> `function <executeScript>: Object reference not set to an instance of an object`。」

→ 这解释了为什么我们必须给物件装 `dsh_global.lua`；也解释了 `set_lua_live.ps1`
（用 `messageID 1` 推整份 Lua）为什么在旧存档上必然失败。

---

## 4. 五条可迁移的经验教训

### ① 架构：走 External Editor API，没有第二条路
tts-editor（Node）、tts-external-api（Rust）两个**独立实现**都是这个协议；
官方文档也是按这个协议写的。
**→ 本项目的「直连 39999 + 游戏内 Lua RPC 层」与主流一致，不需要改架构。**

### ② 状态读取：结构化 API 完胜视觉
- `BALROG` 对比文本状态 / 像素状态 → 文本状态更可靠。
- `Tablescope` 为「照片 → 状态」投入 20 个月。
- `Seeing Without Understanding` 指出 VLM 常常**看着对、推理错**。
**→ 本项目铁律「一律用 Lua 读状态，不用截图反推」有文献支撑，继续执行。**

### ③ 卡牌识别：先读 `FaceURL`，视觉是下策
`cardocr` 一张卡一次 VLM 推理；我们一次哈希比对。
**→ 只有牌面朝下 / 隐藏时才需要视觉。当前唯一需要它的场景就是手牌。**

### ④ 文档：AI 不读长文，是行业公认病
Shino 的一手抱怨 + `TabletopSimulatorCompanion` 专门做 RAG 索引 + 玩家本人
「你的上下文太长了」的提醒 —— 三件事是同一个问题。
**→ HANDOFF 的 `§N` 小节索引 + 按需读，是标准解法，要继续维护。**

### ⑤ 隐藏信息：这是领域空白，不是我们的 bug
手牌不落盘、API 读不到；所有被检索到的项目都在完全信息下工作。
**→ 我们这个卡点没有现成答案可抄。**
**已定方案**：手牌放桌面、牌面朝下，我读 `CustomDeck.FaceURL` 认牌
（玩家看不到牌面 → 公平；我能读到 → 可决策）。**这是当前最优解，放心用。**

---

## 5. 对本项目的可行动项（**2026-10-08 补「落地」列**）

| 优先级 | 行动 | 理由 | 落地 |
|---|---|---|---|
| 高 | **不改架构**，继续 Lua RPC 路线 | 与官方/两个参考实现一致 | ✅ 定案（架构未动） |
| 高 | **更正 `HANDOFF.md` 的 messageID 表**（`5` 不是载入） | 本文 §3.2 | ✅ **已解决**：HANDOFF 里那张表已不存在；`BOOTSTRAP.md` 那份本来就是对的，并已加指向 §3.2 的指针 |
| 高 | **手牌落桌面读 `FaceURL`** 作为隐藏信息的标准解 | 本文 §4⑤ | ✅ 落地为 `TTS_RULES.md`「**隐藏信息的标准解**」（含 4 步操作 + "以物为准"） |
| 中 | 隐藏牌（面朝下）才考虑接 VLM，**日常不接** | 本文 §4③ | ✅ 落地为 `TTS_RULES.md` 的 🚫 条（写清"什么情形才考虑"） |
| 中 | 继续维护 HANDOFF 的小节索引 | 本文 §4④ | ✅ 持续（HANDOFF 已有 §1–§8，并加了 §8 上下文注入） |
| 低 | 参考 `tts-editor` / `tts-external-api` 的协议实现（错误处理/重连） | 比自写更稳 | ⏳ 未做（已有重试；等真出协议级 bug 再对照） |
| 低 | `TabletopSimulatorCompanion` 的「从存档取 PDF URL」技巧 ⇒ 规则书 | 本文 §1.1 | ✅ **已落地且超出预期**：`obj_index.ps1` 现在记 `CustomPDF.PDFUrl`（＋ `src`/`pdfurl` 列）；**实测取到官方规则书 9.1 MB / 15 页**，三步流程与**逐页目录**见 **`local\games\<游戏>\FLOW.md` 附录 A**（⛔ 不进仓库） |

---

## 6. 引用清单

**TTS 生态**
- 官方 External Editor API：https://api.tabletopsimulator.com/externaleditorapi/
- TabletopSimulatorCompanion：https://github.com/libin7099901/TabletopSimulatorCompanion
- cardocr：https://github.com/cloudwu/cardocr
- Shino TTS BOT 日志：https://www.shino-miniatures.fr/web/projets-bot-pour-tabletop-simulator.html
- tts-editor：https://github.com/rolandostar/tts-editor
- tts-external-api：https://github.com/LucasOe/tts-external-api · https://docs.rs/tts-external-api/
- Zavian 脚本库：https://github.com/Zavian/Tabletop-Simulator-Scripts
- Steam 讨论：https://steamcommunity.com/app/286160/discussions/0/6400272499512230488 ·
  https://steamcommunity.com/app/286160/discussions/0/1319962417043058970
- TTS Docs MCP：https://www.pulsemcp.com/servers/doc2mcp-tabletopsimulator

**学术 / 相邻领域**
- PyTAG：https://ieeexplore.ieee.org/document/10333223 ·
  https://tabletopgames.ai/assets/pdf/balla2023pytag.pdf
- RainbowArena：https://dl.acm.org/doi/abs/10.5555/3709347.3743963
- BALROG：https://huggingface.co/papers/2411.13543
- Seeing Without Understanding（ICML 2026）：https://icml.cc/virtual/2026/poster/61694
- Tablescope：https://projekte.ffg.at/projekt/6c98433e-f36b-1410-85f8-00d3c07d99bb

**未能取到正文的来源**（仅标题可信）
- Steam 两个社区讨论帖（抓取被 Steam 拦截）
- linux.do 帖「最近突发奇想让 AI 写桌游发现还挺有意思的」：https://linux.do/t/topic/1540206 （fetch 失败）

---

## 7. 追加调研（2026-10-08）—— **plumbing 层出现开源方案了**

> 触发：准备开源时重新扫了一遍（本文 §0 的"冻结，别重搜"对**结论**仍然有效，但生态确实动了）。
> **§0 那五条结论全部仍然成立**：依然**没有**任何公开项目做到「AI 当玩家在 TTS 里打完整一局」。

### 7.1 新增（本文之前没收录）

| 项目 | 类型 | 为什么重要 |
|---|---|---|
| [Smirk1921/tts-toolkit](https://github.com/Smirk1921/tts-toolkit)（**MIT**，Node ≥24，Windows 优先） | TTS 图包作者工具链 | ⭐ **hub 守护进程（39997）独占唯一的 TTS 连接，再扇出给 CLI / VSCode / MCP agent** —— 正好是我们反复撞的 `ERR listener busy on 39998` 的正解。另有 pack unpack/build（字节级一致）、**游戏内 Lua 测试运行器**、Steam 工坊发布。README 称 2037 用例全绿 |
| [Smirk1921/tts-lua-hub](https://github.com/Smirk1921/tts-lua-hub) | VSCode 扩展 fork | 上游 `rolandostar/tabletopsimulator-lua` 2023-04 起停滞；此 fork 加 hub 集成（不再抢 39998） |
| [haive-games](https://pypi.org/project/haive-games/)（[文档](https://pr1m8.github.io/haive-games/overview.html)） | LLM 桌游 agent 框架（Python） | agent 层的现成框架：可作我们"决策层"的对照面 |
| [damonleelcx/play-with-agents](https://github.com/damonleelcx/play-with-agents) | AI agent 游戏桌（**不是 TTS**） | 自带牌桌 + 主持人 agent + 让 agent 现场设计游戏。⚠️ README 两次 fetch 失败，**只信仓库描述** |
| Code World Models for General Game Playing（arXiv [2510.04542](https://browse-export.arxiv.org/pdf/2510.04542)） | 学术 | 「代码即动作」的通用对局模型 |
| Communication and Verification in LLM Agents under Information Asymmetry（arXiv 2510.25595） | 学术 | ⭐ **信息不对称**下的 LLM agent 协作/校验 —— 与我们的"手牌看不见"同题 |

### 7.2 这些**没有**改变的事

- `tts-toolkit` 是**图包作者工具链**：不做"当玩家"、不读棋局语义、不处理隐藏信息。它替代的是我们的**传输/连接层**（`ttslib.ps1` + `ds.ps1` 的一部分），**替代不了** `play.ps1`（本局控制台）、`live_index`/`diff_hidden`（状态语义）、`install_save2`（把**我们的**桥接烤进存档）、以及整套"每回合 token 预算"的玩法。
- `play-with-agents` 是**另一个平台**（自带牌桌），不是"在 TTS 里代打"。
- 所以本项目的**差异化仍在"玩家层"**：状态语义化读取 · 隐藏信息纪律 · 每回合 token/耗时预算 · 人机分工（人只决策 + 点结束回合）。

### 7.3 新增可行动项（**2026-10-08 补「落地」列**）

| 优先级 | 行动 | 理由 | 落地 |
|---|---|---|---|
| **高** | **评估接入 `tts-hub`（39997）**：让脚本 / watcher / VSCode / MCP agent 共享一条 TTS 连接 | 一次性干掉 `LISTENERBUSY` 重试与"后台 watcher 抢 39998" | ⏳ **暂缓（定案）**：现有 `Bridge`/`Send-Tts` 重试已够稳，而接入是**协议改动**（+ 要 Node ≥24 常驻 hub）。**触发条件**：真出现并发抢占导致丢包，或我们要给别的工具开 TTS 出口 |
| 中 | 若接入 hub，`ttslib.ps1` 可缩到"只会连 39997" | 少一层自维护协议代码 | ⏳ 取决于上一行 |
| 中 | 读 arXiv 2510.25595（信息不对称）＋ `haive-games`，找可搬的隐藏信息/校验模式 | §4⑤ 有理论 | ✅ **已完成** ⇒ 见 §7.4（结论已落进 `TTS_RULES.md` 的"以物为准"条） |
| 低 | 游戏内 Lua 测试运行器（`tts test`） | 改 `dsh_global.lua` 只能人肉重载存档验证 | ⏳ **暂缓（定案）**：要 Node ≥24 ＋ hub，且每次跑都要重装存档；离线自测（`tts\tests\`）已覆盖**不依赖 TTS 的那部分**逻辑 |
| 低 | 把 `tts-toolkit` / `haive-games` 写进 README 的"相关项目" | 开源项目应当致谢并定位自己 | ✅ 已写进 `README.md` / `README.en.md` 的 **Related work** 段 |

⚠️ **不要**因为"有现成工具链"就去重写我们的 PowerShell 层：接入 hub 是一次**协议改动**（验收标准 = 现有 4 个脚本 + 2 个 watcher 全绿），不是重写。

### 7.4 信息不对称 / haive-games 的**可搬结论**（2026-10-08，子代理读原文提炼）

**可搬（已落地）**：
- **verifier 前置**：出动作/开口前先自检 —— 这个动作在当前 state diff 下合法吗？这条信息是不是**已经在 notebook 公开记录里**（重复披露＝白烧 token）？
  论文里带 verifier 的配置 **89.3% vs 无 verifier 58.7%**。
- **通信即代价**：该文把"一次披露"算作一个回合 ⇒ 与我们"每回合 token 预算"同构：**一次追问必须有判别力**（能二分/排除某候选）才问。
- **定向索要 > 泛泛自述**：该露的露（要人配合时），但别自述手牌。

**明确不可搬（别再研究）**：
- 那篇的增益核心是 **SFT**（planner 造约 1 万条轨迹微调）＋ best-of-n 采样 ⇒ 我们**没有标注轨迹也没有仿真器**，只搬训练无关的那半。
- `haive-games` 的 deception detection / trust modeling 是**绑定它自己 `GameStateManager` 的声明式外壳**（大量 `pass` 桩 ＋ personality 超参）；
  我们的真源是 **TTS state diff ＋ notebook**，接进来只会得到**与桌面不一致的镜像状态** ⇒ **不装**（仅作命名参考）。
---

## 8. 指令注入（`AGENTS.md` 等）的生态做法（**2026-10-09 追加调研**）

> 动机：本项目为"**通用 ≠ 本局**"与"**全局槽污染**"做了一整套取舍（槽位定义见 `tts\docs\INJECTION.md`）。
> 这里把生态做法核对一遍，**避免重复研究**；结论见 **§8.3**。

### 8.1 五类做法（每类都有真实实现）

| 家族 | 做法 | 代表实现 | 对"污染"的效果 |
|---|---|---|---|
| ① 标准只管项目内 | 仓库根 ＋ 可嵌套，**离被改文件最近的赢**；规范里**没有**用户级文件 | [agents.md](https://agents.md/)（Linux Foundation 托管，6 万+ 项目） | 说明**"全局槽"是各工具的私有扩展** ⇒ 不存在跨工具的统一开关 |
| ② **按路径/文件作用域** ⭐ | `globs:`（相关文件进上下文才附加）· 嵌套 `AGENTS.md`（子目录更具体者优先）· 只在 `@`-提及时才用 | [Cursor 规则文档](https://cursor.com/docs/rules.md)：`alwaysApply` / `globs` / `description` / 手动 —— 四种生效方式 | **生态里最通用**：用"位置 + 匹配"表达作用域，而不是一个全局文件覆盖全世界 |
| ③ 显式清单取代隐式全局 | 配置里**点名**要读哪些文件（支持 glob、甚至远程 URL） | [OpenCode `instructions`](https://opencode.ai/docs/rules/) · Aider `read:` · Gemini CLI `context.fileName` | 不列就不注入 ✓ |
| ④ 给全局槽开关 | 环境变量/配置精确关掉某一类 | OpenCode `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1` / `OPENCODE_DISABLE_CLAUDE_CODE=1` / [`instructionMode` PR](https://github.com/anomalyco/opencode/pull/33499)；Claude Agent SDK 可"不加载用户/项目/本地配置"；`CLAUDE_CONFIG_DIR` 可搬走配置目录 | 能关，但**都是工具私有**；**DSH 没有这个开关** |
| ⑤ 一份源 → 生成到各项目 | 版本化规则源编译成各工具的规则文件 | [rulesync](https://github.com/dyoshikawa/rulesync/blob/main/skills/rulesync/cli-commands.md) | 跨项目一致性由**构建**保证 ⇒ 运行时的全局槽可以空着 |

**两类"组织/工具级"补充机制**（不是解污染，但要知道它们存在）：

- **按仓库开关"全局东西"的第三方层**：[`harness-scope`](https://github.com/shimo4228/harness-scope)（Claude Code mod）——"按仓库用命名 profile 开关全局 skills / agents / rules / tools；在写作仓库里一行关掉 101 个 skill 中的 94 个"⇒ 这正是"**按项目关掉全局污染**"的现成实现。
- **组织强制**：Cursor 的 **Team Rules** 可 **Enforce**（成员无法关闭），优先级 **Team → Project → User**。⇒ 顺带确认一件事：**项目级本来就压过用户级**，"污染"是可被覆盖的；真正危险的是**把项目专属知识写进用户级**（无处覆盖，且每个项目都付费注入）。

### 8.2 与本项目的对照

| 维度 | 生态做法 | 本项目（2026-10-09 现状） |
|---|---|---|
| 全局槽 | 多数工具**保留 ＋ 给开关** | ⭐ **机器上不放**（方案 A）⇒ 任何启动方式零注入，不依赖任何工具的开关 |
| 作用域 | **glob / 路径 / 嵌套** | 按**文档频率**分层（`PLAY.md` 每回合 · `MAINTENANCE.md` 改代码前 · `INJECTION.md` 装机器时）· ⚠️ **没有 glob 级作用域** |
| 预算 | 只有"规则写短些"的建议 | ⭐ **可测量字节预算 ＋ 测试强制**（3,840 / 4,096 B，超限即红）—— 生态里未见同等做法 |
| 漂移 | 生成器（rulesync）或人工纪律 | 指针制 ＋ `test_doc_refs.ps1` 查死链 |
| 开源剥离 | 少见 | ⭐ `OPENSOURCE-TEMP` 标记 ＋ 发布前一条命令清理 |
| 防假绿 | 未见 | ⭐ `run_all.ps1`：**退出码 0 且输出含成功标志**才算过 |

**与生态对齐的两条官方建议**（可作"我们没走偏"的旁证）：

- Cursor 官方：**"reference files instead of copying the contents —— keeps rules short and prevents them from becoming stale"** ⇒ 与我们"一处真源 ＋ 只留指针"一致 ✓
- Cursor 官方：**"keep rules under 500 lines · split into composable rules · add rules only when the agent repeats a mistake"** ⇒ 与我们"按频率分层 ＋ 只在付过代价后才加规则"一致 ✓

### 8.3 可搬 / 不可搬（**结论，别再重搜**）

- ✅ **可搬（值得做）**：给规则文件加 **frontmatter（`alwaysApply` / `globs`）**，再用一个生成器把它们落到"每回合 / 按需"两条路上 —— 这正是 rulesync 的位置。当初不采用是因为"项目模式要配对模板"；现在 `INJECTION.md` 已把槽位与预算写死，**可以重新评估**。
- ❌ **不可搬**：① `harness-scope` 是 **Claude Code 专属**（改它的 skill/agent 加载），DSH 侧没有对应面；② OpenCode 的开关与 `instructionMode` 是**该工具私有**，而 DSH 的 `USER_GLOBAL_FILE` 是常量 ⇒ 只能"不放那份"；③ Team Rules 那种**组织强制**我们不需要（单人 ＋ 开源）。
- ⛔ **明确不做**：在**真的出现第二个消费者**之前，不引入"多工具规则生成流水线"（现在只有 DSH 一个消费者 ⇒ 生成器是纯开销）。
