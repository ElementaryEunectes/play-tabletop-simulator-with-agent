# 先行研究：让 AI 在 Tabletop Simulator 里打桌游

> **什么时候读我**：想查先例、或怀疑"这件事别人做过没有"的时候。**本文冻结 —— 别重搜、别重写**（可搬/不可搬结论都在 §7.4 与 §8.3）。

**调研日期**：2026-10-04 · **动机**：本项目的架构（外部进程 ＋ 游戏内 Lua RPC 层 ＋ 代打三个座位）是否是正路？有没有现成方案或别人踩过的坑可抄？

---

## 0. 结论摘要（先看这五条）

> ⚠️ **2026-10-08 追加调研见 §7**：下面五条**仍然成立**（依然没有"AI 当玩家打完整一局"的公开实现），
> 但 **plumbing 层出现了开源方案**（`tts-toolkit` 的 hub/MCP 扇出），且新增了 agent 框架与两篇相关论文。

1. **「AI 当玩家在 TTS 里打完整一局桌游」的公开实现 = 0 个**（GitHub / Steam 社区 / arXiv 全搜过）⇒ 我们做的是生态空白。
2. **所有 TTS 自动化都走同一条路**：官方 **External Editor API**（TTS 听 `39999`，编辑器听 `39998`）—— tts-editor、tts-external-api 两个独立实现都是它，**没人绕过** ⇒ 我们的直连 ＋ Lua RPC 是主流正解。
3. **现有「LLM × TTS」项目只做规则问答、不碰棋子**（代表：`TabletopSimulatorCompanion` = TTS 内提问 → Python ＋ RAG 查规则书 → 回话，操作仍靠人）。
4. **隐藏信息（手牌）在 TTS API 层拿不到 —— 这很可能就是没人做成「AI 当玩家」的技术根因**：手牌是**会话状态**、不落盘（`HandTrigger` 在存档里是空容器），所有被检索到的项目都在完全信息下工作 ⇒ 「③ 弃手牌做不了」是领域空白，不是配置问题。
5. **行业共性痛点 = 长文档 AI 不读 ＋ 状态读取靠猜** ⇒ 正是本项目要写**按小节索引的 HANDOFF**、**一律用 Lua 读状态不用截图反推**的原因。

---

## 1. 直接相关：TTS 上的 AI 项目

| 项目 | 类型 | 关键事实 |
|---|---|---|
| **TabletopSimulatorCompanion**（libin7099901） | LLM 规则问答 | 唯一完整的「LLM × TTS」项目（Python ＋ Lua Mod，v0.3.4，2025-06） |
| **cloudwu/cardocr** | 卡牌 OCR | 卡面识别：`ollama` ＋ `qwen3-vl`；**测试图取自 TTS 创意工坊 mod** |
| **shino-miniatures：BOT pour TTS** | 规则 BOT 实践日志 | 2026-01 起用 ChatGPT 给《Confrontation》做 BOT |
| **rolandostar/tts-editor** | 协议参考实现（Node/TS） | 完整实现 External Editor API 全部 4 发 / 8 收消息类型，附假 TTS 后端 |
| **LucasOe/tts-external-api** | 协议参考实现（Rust） | 同上；文档明确「API 结构体绑定 `39999` 监听」 |
| **Steam 两个社区提问**（Can I script an AI? ・ How to play game with AI??） | 社区提问 | 共识 = 没有现成的，自己写（正文被 Steam 拦截，仅标题可信） |
| **Zavian/Tabletop-Simulator-Scripts** | Lua 脚本库 | 纯自动化（不是 AI），可作物件操作写法参考 |

（链接全部见 §6，本文只在需要"去哪找"的地方给 URL。）

### 1.1 `TabletopSimulatorCompanion` —— 值得细看的一个
- **架构**：TTS 内 Lua Mod（`tc_mod.lua`）＋ 本地 Flask 服务端（`TTSAssistantServer`）；玩家在 TTS 里打 `@tc 你的问题`，服务端 RAG 后把答案显示给对应玩家；Langchain ＋ FAISS ＋ Sentence-Transformers，LLM 可换 Gemini / Ollama / OpenAI。
- **值得抄的两点**：① **它的核心价值是「把规则书变成可检索索引」，不是「AI 会玩」** ⇒ 印证我们「按小节索引文档」；② **它教了怎么从 TTS 数据里拿规则书 URL** —— 右键桌面 PDF 物件 → 自定义，或直接在存档/工坊 JSON 里找 `Custom_PDF` 的 `PDFUrl` / `FileURL` ⇒ **和我们读 `CustomDeck.FaceURL` 是同一招**：TTS 存档是结构化元数据宝库。
- **它没做的**：读棋盘状态、移动棋子、代打、隐藏信息。

### 1.2 `cardocr` —— 同行的视觉路线（我们的对照面）
- 做法：对**卡面图片**调 `ollama` 跑 `qwen3-vl`，抽文本 ＋ 图标语义（把 `[GEM]`、`[ALLY]` 翻译成语义标签）。
- **成本结构完全不同**：一张卡一次 VLM 推理（慢、可能错、要模型权重）；**我们直接读 `CustomDeck.<CardID>.FaceURL` 的 40 位哈希**（免费、确定、可去重）。
- **结论**：**TTS 里优先读 `FaceURL`，视觉只在牌面朝下 / 隐藏时才需要** —— 这是本项目相对 cardocr 的核心优势，别丢掉。附注：它的测试样本就是 TTS 工坊 mod 卡图 ⇒ 大家做法一致（我们读存档，它读工坊文件）。

### 1.3 Shino 的 BOT 日志 —— 唯一找到的「LLM 在 TTS 里做规则执行」一手实践
作者的抱怨原话（法语，2026-01-22）：「把所有东西都给 AI 讲清楚相当费劲 —— 它明明手上有文件（规则、档案、技能……），却似乎并不总是去读、去遵守。」
- 这正是我们反复见到的现象：**长文档给了 AI，AI 不一定用**。唯一有效对策：**不要一次性喂全文，要给索引 ＋ 按需切片**（= 本项目 HANDOFF 的小节索引）。
- 另一个观察：即使有全部规则文本，**规则执行的正确性仍要靠人兜底**（他也在人工核对）。

### 1.4 社区现状：问的人多，做的人没有
Steam 那两个高热度提问都只拿到「自己写脚本」类回答 ⇒ **没有官方 AI 对手，也没有第三方成品。**

---

## 2. 相邻领域：不是 TTS，但方法论可搬

| 项目 | 是什么 | 可搬的东西 |
|---|---|---|
| **PyTAG / TAG Framework** | 把桌游封装成 RL 环境的框架 | 状态表示要**结构化**、动作空间要**离散可枚举** —— 我们 `act:` 动词白名单正是这个思路 |
| **RainbowArena** | RL + LLM 双路线的多智能体桌游工具包 | 多座位代打（本项目要同时演 P2/P3/P4）在文献里是独立课题 |
| **BALROG** | LLM/VLM 当游戏 agent 的基准 | 明确对比「文本状态」vs「像素状态」两种输入 —— 文本状态显著更可靠 |
| **Seeing Without Understanding**（ICML 2026） | 拆解 VLM 打游戏的「感知 / 推理 / 模拟」三段 | **看着对 ≠ 推理对**。截图上「牌在那儿」不代表我理解对了局面 |
| **Tablescope**（FFG / TU Graz，2022–2024） | 用 CV 把**真实桌面**照片变成游戏状态 | 说明了视觉路线的真实成本：语义分割 ＋ one-shot learning ＋ 合成图增强，20 个月项目 |
| **Tabletop Simulator Docs MCP** | 把 TTS 官方文档做成 MCP server | 只提供文档查询，不提供操作 |

（链接 ⇒ §6。）**读法**：`Tablescope` 花了 20 个月 ＋ 一个博士团队做「从照片认桌面」；**TTS 里我们不需要做这件事** —— `getPosition` / 存档 JSON 已经把答案给了 ⇒ **任何「截图反推坐标」的冲动都应该被这条压下去。**

---

## 3. 官方 API 事实（[External Editor API 文档](https://api.tabletopsimulator.com/externaleditorapi/)）

### 3.1 端口方向
**编辑器监听 `39998`；TTS 监听 `39999`** ⇒ **TTS → 编辑器**（我们收）＝ `39998`；**编辑器 → TTS**（我们发）＝ `39999`。

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

**更正**：本项目 `HANDOFF.md` 旧文写「`5`（载入）」是**错的** —— 载入是 `1`，`5` 是 **ExecuteLua 的返回值**；过滤行为（只认 `messageID 4`）一直是对的，只是标签标错了。**顺带一条**：`messageID 5` 能直接拿返回值 ⇒ 官方本来就有「执行 Lua 并取回结果」的通道，不必用 `error("VALUE="..x)` 硬凑；但我们的 `messageID 4` 通道已稳定，**不必改**。

### 3.3 一个容易忽略的硬前提
要对某个物件执行 Lua，**该物件必须已经在 TTS 里关联了脚本**；否则报 `function <executeScript>: Object reference not set to an instance of an object` ⇒ 这解释了为什么我们必须给物件装 `dsh_global.lua`，也解释了 `set_lua_live.ps1`（用 `messageID 1` 推整份 Lua）为什么在旧存档上必然失败。

---

## 4. 五条可迁移的经验教训

| # | 结论 | 证据 / 出处 ⇒ 本项目决策 |
|---|---|---|
| ① 架构 | 走 External Editor API，**没有第二条路** | tts-editor（Node）＋ tts-external-api（Rust）两个**独立实现**都是它，官方文档也按它写 ⇒ **「直连 39999 ＋ 游戏内 Lua RPC 层」与主流一致，不改架构** |
| ② 状态读取 | **结构化 API 完胜视觉** | `BALROG`（文本 vs 像素 → 文本显著更可靠）· `Tablescope`（为"照片 → 状态"投入 20 个月）· `Seeing Without Understanding`（VLM 常常**看着对、推理错**）⇒ **铁律「一律用 Lua 读状态，不用截图反推」有文献支撑，继续执行** |
| ③ 卡牌识别 | **先读 `FaceURL`，视觉是下策** | `cardocr` 一张卡一次 VLM 推理 vs 我们一次哈希比对 ⇒ **只有牌面朝下 / 隐藏时才需要视觉 —— 当前唯一场景就是手牌** |
| ④ 文档 | **AI 不读长文，是行业公认病** | Shino 的一手抱怨 ＋ `TabletopSimulatorCompanion` 专门做 RAG 索引 ＋ 玩家本人「你的上下文太长了」= 同一个问题 ⇒ **HANDOFF 的 `§N` 小节索引 ＋ 按需读是标准解法，要继续维护** |
| ⑤ 隐藏信息 | **这是领域空白，不是我们的 bug** | 手牌不落盘、API 读不到；所有被检索到的项目都在完全信息下工作 ⇒ **没有现成答案可抄** ⇒ **已定方案**：手牌放桌面、牌面朝下，我读 `CustomDeck.FaceURL` 认牌（玩家看不到牌面 → 公平；我能读到 → 可决策）—— **当前最优解，放心用** |

---

## 5. 对本项目的可行动项（**2026-10-08 补「落地」列**）

| 优先级 | 行动（理由） | 落地 |
|---|---|---|
| 高 | **不改架构**，继续 Lua RPC 路线（§4①） | ✅ 定案（架构未动） |
| 高 | **更正 `HANDOFF.md` 的 messageID 表**（§3.2） | ✅ **已解决**：HANDOFF 里那张表已不存在；`BOOTSTRAP.md` 那份本来就是对的，并已加指向 §3.2 的指针 |
| 高 | **手牌落桌面读 `FaceURL`** 作为隐藏信息的标准解（§4⑤） | ✅ 落地为 `TTS_RULES.md`「**隐藏信息的标准解**」（含 4 步操作 ＋ "以物为准"） |
| 中 | 隐藏牌（面朝下）才考虑接 VLM，**日常不接**（§4③） | ✅ 落地为 `TTS_RULES.md` 的 🚫 条（写清"什么情形才考虑"） |
| 中 | 继续维护 HANDOFF 的小节索引（§4④） | ✅ 持续（HANDOFF 已有 §1–§8，并加了 §8 上下文注入） |
| 低 | 参考 `tts-editor` / `tts-external-api` 的协议实现（错误处理/重连） | ⏳ 未做（已有重试；等真出协议级 bug 再对照） |
| 低 | `TabletopSimulatorCompanion` 的「从存档取 PDF URL」技巧 ⇒ 规则书（§1.1） | ✅ **已落地且超出预期**：`obj_index.ps1` 现在记 `CustomPDF.PDFUrl`（＋ `src`/`pdfurl` 列）；**实测取到官方规则书 9.1 MB / 15 页**，三步流程与**逐页目录**见 **`local\games\<游戏>\FLOW.md` 附录 A**（⛔ 不进仓库） |

---

## 6. 引用清单

**TTS 生态**：官方 External Editor API https://api.tabletopsimulator.com/externaleditorapi/ · TabletopSimulatorCompanion https://github.com/libin7099901/TabletopSimulatorCompanion · cardocr https://github.com/cloudwu/cardocr · Shino BOT 日志 https://www.shino-miniatures.fr/web/projets-bot-pour-tabletop-simulator.html · tts-editor https://github.com/rolandostar/tts-editor · tts-external-api https://github.com/LucasOe/tts-external-api · Zavian 脚本库 https://github.com/Zavian/Tabletop-Simulator-Scripts · Steam 讨论 https://steamcommunity.com/app/286160/discussions/0/6400272499512230488 · https://steamcommunity.com/app/286160/discussions/0/1319962417043058970 · TTS Docs MCP https://www.pulsemcp.com/servers/doc2mcp-tabletopsimulator · tts-toolkit https://github.com/Smirk1921/tts-toolkit · tts-lua-hub https://github.com/Smirk1921/tts-lua-hub · haive-games https://pypi.org/project/haive-games/ （文档 https://pr1m8.github.io/haive-games/overview.html）· play-with-agents https://github.com/damonleelcx/play-with-agents

**学术 / 相邻领域**：PyTAG https://ieeexplore.ieee.org/document/10333223 · https://tabletopgames.ai/assets/pdf/balla2023pytag.pdf · RainbowArena https://dl.acm.org/doi/abs/10.5555/3709347.3743963 · BALROG https://huggingface.co/papers/2411.13543 · Seeing Without Understanding（ICML 2026）https://icml.cc/virtual/2026/poster/61694 · Tablescope https://projekte.ffg.at/projekt/6c98433e-f36b-1410-85f8-00d3c07d99bb · Code World Models https://browse-export.arxiv.org/pdf/2510.04542 · 信息不对称 arXiv 2510.25595

**指令注入生态**（⇒ §8）：agents.md https://agents.md/ · Cursor 规则 https://cursor.com/docs/rules.md · OpenCode https://opencode.ai/docs/rules/ · `instructionMode` PR https://github.com/anomalyco/opencode/pull/33499 · rulesync https://github.com/dyoshikawa/rulesync/blob/main/skills/rulesync/cli-commands.md · harness-scope https://github.com/shimo4228/harness-scope

**未能取到正文的来源**（仅标题可信）：Steam 两个社区讨论帖（抓取被拦截）· linux.do 帖「最近突发奇想让 AI 写桌游发现还挺有意思的」https://linux.do/t/topic/1540206 （fetch 失败）

---

## 7. 追加调研（2026-10-08）—— **plumbing 层出现开源方案了**

> 触发：准备开源时重新扫了一遍（§0 的"冻结，别重搜"对**结论**仍然有效，但生态确实动了）。**§0 那五条结论全部仍然成立**：依然**没有**任何公开项目做到「AI 当玩家在 TTS 里打完整一局」。

### 7.1 新增（本文之前没收录）

| 项目 | 类型 | 为什么重要 |
|---|---|---|
| **Smirk1921/tts-toolkit**（**MIT**，Node ≥24，Windows 优先） | TTS 图包作者工具链 | ⭐ **hub 守护进程（39997）独占唯一的 TTS 连接，再扇出给 CLI / VSCode / MCP agent** —— 正是我们反复撞的 `ERR listener busy on 39998` 的正解。另有 pack unpack/build（字节级一致）、**游戏内 Lua 测试运行器**、Steam 工坊发布（README 称 2037 用例全绿） |
| **Smirk1921/tts-lua-hub** | VSCode 扩展 fork | 上游 `rolandostar/tabletopsimulator-lua` 2023-04 起停滞；此 fork 加 hub 集成（不再抢 39998） |
| **haive-games** | LLM 桌游 agent 框架（Python） | agent 层的现成框架：可作我们"决策层"的对照面 |
| **damonleelcx/play-with-agents** | AI agent 游戏桌（**不是 TTS**） | 自带牌桌 ＋ 主持人 agent ＋ 让 agent 现场设计游戏。⚠️ README 两次 fetch 失败，**只信仓库描述** |
| **Code World Models for General Game Playing**（arXiv [2510.04542](https://browse-export.arxiv.org/pdf/2510.04542)） | 学术 | 「代码即动作」的通用对局模型 |
| **Communication and Verification in LLM Agents under Information Asymmetry**（arXiv 2510.25595） | 学术 | ⭐ **信息不对称**下的 LLM agent 协作/校验 —— 与我们的"手牌看不见"同题 |

（其余链接 ⇒ §6。）

### 7.2 这些**没有**改变的事

- `tts-toolkit` 是**图包作者工具链**：不做"当玩家"、不读棋局语义、不处理隐藏信息 ⇒ 它替代的是**传输/连接层**（`ttslib.ps1` ＋ `ds.ps1` 的一部分），**替代不了** `play.ps1`（本局控制台）、`live_index`/`diff_hidden`（状态语义）、`install_save2`（把**我们的**桥接烤进存档）、以及整套"每回合 token 预算"；`play-with-agents` 是**另一个平台**（自带牌桌），不是"在 TTS 里代打"。
- ⇒ 本项目的**差异化仍在"玩家层"**：状态语义化读取 · 隐藏信息纪律 · 每回合 token/耗时预算 · 人机分工（人只决策 ＋ 点结束回合）。

### 7.3 新增可行动项（**2026-10-08 补「落地」列**）

| 优先级 | 行动（理由） | 落地 |
|---|---|---|
| **高** | **评估接入 `tts-hub`（39997）**：让脚本 / watcher / VSCode / MCP agent 共享一条 TTS 连接（一次性干掉 `LISTENERBUSY` 重试与"后台 watcher 抢 39998"） | ⏳ **暂缓（定案）**：现有 `Bridge`/`Send-Tts` 重试已够稳，而接入是**协议改动**（＋ 要 Node ≥24 常驻 hub）。**触发条件**：真出现并发抢占导致丢包，或要给别的工具开 TTS 出口 |
| 中 | 若接入 hub，`ttslib.ps1` 可缩到"只会连 39997"（少一层自维护协议代码） | ⏳ 取决于上一行 |
| 中 | 读 arXiv 2510.25595（信息不对称）＋ `haive-games`，找可搬的隐藏信息/校验模式（§4⑤ 有理论） | ✅ **已完成** ⇒ 见 §7.4（结论已落进 `TTS_RULES.md` 的"以物为准"条） |
| 低 | 游戏内 Lua 测试运行器（`tts test`）：改 `dsh_global.lua` 只能人肉重载存档验证 | ⏳ **暂缓（定案）**：要 Node ≥24 ＋ hub，且每次跑都要重装存档；离线自测（`tts\tests\`）已覆盖**不依赖 TTS 的那部分** |
| 低 | 把 `tts-toolkit` / `haive-games` 写进 README 的"相关项目" | ✅ 已写进 `README.md` / `README.en.md` 的 **Related work** 段 |

⚠️ **不要**因为"有现成工具链"就去重写我们的 PowerShell 层：接入 hub 是一次**协议改动**（验收标准 = 现有 4 个脚本 ＋ 2 个 watcher 全绿），不是重写。

### 7.4 信息不对称 / haive-games 的**可搬结论**（2026-10-08，子代理读原文提炼）

**可搬（已落地）**：
- **verifier 前置**：出动作/开口前先自检 —— 这个动作在当前 state diff 下合法吗？这条信息是不是**已经在 notebook 公开记录里**（重复披露＝白烧 token）？论文里带 verifier 的配置 **89.3% vs 无 verifier 58.7%**。
- **通信即代价**：该文把"一次披露"算作一个回合 ⇒ 与我们"每回合 token 预算"同构：**一次追问必须有判别力**（能二分/排除某候选）才问。
- **定向索要 > 泛泛自述**：该露的露（要人配合时），但别自述手牌。

**明确不可搬（别再研究）**：
- 那篇的增益核心是 **SFT**（planner 造约 1 万条轨迹微调）＋ best-of-n 采样 ⇒ 我们**没有标注轨迹也没有仿真器**，只搬训练无关的那半。
- `haive-games` 的 deception detection / trust modeling 是**绑定它自己 `GameStateManager` 的声明式外壳**（大量 `pass` 桩 ＋ personality 超参）；我们的真源是 **TTS state diff ＋ notebook**，接进来只会得到**与桌面不一致的镜像状态** ⇒ **不装**（仅作命名参考）。
---

## 8. 指令注入（`AGENTS.md` 等）的生态做法（**2026-10-09 追加调研**）

> 动机：本项目为"**通用 ≠ 本局**"与"**全局槽污染**"做了一整套取舍（槽位定义见 `tts\docs\INJECTION.md`）。这里把生态做法核对一遍，**避免重复研究**；结论见 **§8.3**。

### 8.1 五类做法（每类都有真实实现）

| 家族 | 做法 | 代表实现 | 对"污染"的效果 |
|---|---|---|---|
| ① 标准只管项目内 | 仓库根 ＋ 可嵌套，**离被改文件最近的赢**；规范里**没有**用户级文件 | agents.md（Linux Foundation 托管，6 万+ 项目） | 说明**"全局槽"是各工具的私有扩展** ⇒ 不存在跨工具的统一开关 |
| ② **按路径/文件作用域** ⭐ | `globs:`（相关文件进上下文才附加）· 嵌套 `AGENTS.md`（子目录更具体者优先）· 只在 `@`-提及时才用 | Cursor 规则文档：`alwaysApply` / `globs` / `description` / 手动（四种生效方式） | **生态里最通用**：用"位置 ＋ 匹配"表达作用域，而不是一个全局文件覆盖全世界 |
| ③ 显式清单取代隐式全局 | 配置里**点名**要读哪些文件（支持 glob，甚至远程 URL） | OpenCode `instructions` · Aider `read:` · Gemini CLI `context.fileName` | 不列就不注入 ✓ |
| ④ 给全局槽开关 | 环境变量/配置精确关掉某一类 | OpenCode `OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1` / `OPENCODE_DISABLE_CLAUDE_CODE=1` / `instructionMode` PR；Claude Agent SDK 可"不加载用户/项目/本地配置"；`CLAUDE_CONFIG_DIR` 可搬走配置目录 | 能关，但**都是工具私有**；**DSH 没有这个开关** |
| ⑤ 一份源 → 生成到各项目 | 版本化规则源编译成各工具的规则文件 | rulesync | 跨项目一致性由**构建**保证 ⇒ 运行时的全局槽可以空着 |

**两类"组织/工具级"补充机制**（不是解污染，但要知道它们存在）：① `harness-scope`（Claude Code mod）—— 按仓库用命名 profile 开关全局 skills / agents / rules / tools（"写作仓库里一行关掉 101 个 skill 中的 94 个"）⇒ "按项目关掉全局污染"的现成实现；② Cursor 的 **Team Rules** 可 **Enforce**，优先级 **Team → Project → User** ⇒ 顺带确认：**项目级本来就压过用户级**，"污染"可被覆盖；真正危险的是**把项目专属知识写进用户级**（无处覆盖，且每个项目都付费注入）。（本表链接 ⇒ §6。）

### 8.2 与本项目的对照

| 维度 | 生态做法 | 本项目（2026-10-09 现状） |
|---|---|---|
| 全局槽 | 多数工具**保留 ＋ 给开关** | ⭐ **机器上不放**（方案 A）⇒ 任何启动方式零注入，不依赖任何工具的开关 |
| 作用域 | **glob / 路径 / 嵌套** | 按**文档频率**分层（`PLAY.md` 每回合 · `MAINTENANCE.md` 改代码前 · `INJECTION.md` 装机器时）· ⚠️ **没有 glob 级作用域** |
| 预算 / 漂移 | 只有"规则写短些"的建议；生成器（rulesync）或人工纪律 | ⭐ **可测量字节预算 ＋ 测试强制**（3,840 / 4,096 B，超限即红）· 指针制 ＋ `test_doc_refs.ps1` 查死链 |
| 工程纪律（生态里少见/未见） | —— | ⭐ `OPENSOURCE-TEMP` 标记 ＋ 发布前一条命令清理 · ⭐ `run_all.ps1`：**退出码 0 且输出含成功标志**才算过（防假绿） |

**与生态对齐的两条 Cursor 官方建议**（"我们没走偏"的旁证）：① *"reference files instead of copying the contents —— keeps rules short and prevents them from becoming stale"* ⇒ 与我们"一处真源 ＋ 只留指针"一致 ✓；② *"keep rules under 500 lines … add rules only when the agent repeats a mistake"* ⇒ 与我们"按频率分层 ＋ 只在付过代价后才加规则"一致 ✓。

### 8.3 可搬 / 不可搬（**结论，别再重搜**）

- ✅ **可搬（值得做）**：给规则文件加 **frontmatter（`alwaysApply` / `globs`）**，再用一个生成器把它们落到"每回合 / 按需"两条路 —— 这正是 rulesync 的位置（当初不采用是因为"项目模式要配对模板"；现在 `INJECTION.md` 已把槽位与预算写死，**可以重新评估**）。
- ❌ **不可搬**：① `harness-scope` 是 **Claude Code 专属**（改它的 skill/agent 加载），DSH 侧没有对应面；② OpenCode 的开关与 `instructionMode` 是**该工具私有**，而 DSH 的 `USER_GLOBAL_FILE` 是常量 ⇒ 只能"不放那份"；③ Team Rules 那种**组织强制**我们不需要（单人 ＋ 开源）。
- ⛔ **明确不做**：在**真的出现第二个消费者**之前，不引入"多工具规则生成流水线"（现在只有 DSH 一个消费者 ⇒ 生成器是纯开销）。

## 9. 追加调研（2026-10-12）—— 通道 / 存档 / 本地化 三层的现成件

> ⚠️ **状态：全部未实测**。本沙箱里 `pwsh` 出网被挡（`Invoke-WebRequest`/`WebClient` 一律"基础连接已经关闭"），`web_fetch` 对 `raw.githubusercontent` / fandom / biligame 常超时 ⇒ 本节只有**搜索摘要级证据**，判据要等一台能出网的机器。
> ⭐ **纪律（采用即标）**：凡是**采用 / 借鉴**下面任何一件 ⇒ 在**本文件标源（项目名 ＋ 链接 ＋ 许可）**，并在 `MAINTENANCE.md` §5 写清"我们哪件工具是它的对应物"；⛔ 别当成自己写的。

### 9.1 与我们手写的那层直接重叠（优先对照）

| 项目 | 是什么 | 对应我们的 | 备注 |
|---|---|---|---|
| [tts-editor](https://github.com/matanlurey/tts-editor)（[fork](https://github.com/rolandostar/tts-editor)） | TypeScript 版 External Editor API（39999） | `tts\tts_api.ps1` | ⚠️ **2026-10-12 查证：原版已 `archived`、最后推送 2023-02；fork 2022 年后停更、0 star** ⇒ **不要依赖它**（先前写成"最该看"是过头了）。**许可 = `null`（无许可证）** ⇒ **只能读思路、不能抄代码**。真收获 ⇒ §9.5 |
| [@smirk1921/tts-toolkit](https://www.npmjs.com/package/@smirk1921/tts-toolkit) | 独占回复端口的 **hub / daemon** | `tts\tools\tts_hub.ps1` | 本仓 hub 就是照这个方案做的（⇒ §7）⇒ 不必换，跟它的更新即可 |
| [tts-community/api](https://github.com/tts-community/api) | **社区维护**的 Lua API 文档 | 我们注释里引的官方站 | 查字段的第二来源 |
| [TTS Tools (Community Fork)](https://open-vsx.org/extension/eunomiac/tts-tools) | VS Code 扩展 | — | 编辑 Lua / 管 mod 的候选 |

### 9.2 存档层批量操作（改文本要走的载体）

| 项目 | 是什么 | 备注 |
|---|---|---|
| [DiscreteTom/tts-card-naming-tool](https://github.com/DiscreteTom/tts-card-naming-tool) | 网页工具：**批量重命名存档里的卡** | ⭐ "机翻后写回卡名"的现成载体 ⇒ 见 §9.3 |
| [benjamin-dobell/ge_tts](https://github.com/benjamin-dobell/ge_tts) | TTS **Save Manager** | README 未抓到（fetch 超时）⇒ **待实测** |

### 9.3 外文 mod 本地化（"不烧 token 的机翻"候选件）

| 项目 | 是什么 | 在我们链条里的位置 |
|---|---|---|
| [LibreTranslate](https://docs.libretranslate.com/guides/supported_languages/) | **可自托管、离线**的翻译服务（Argos 模型底座） | ⭐ **引擎**（"0 token"的关键件） |
| [cloudwu/cardocr](https://tool.lu/es_ES/library/3eq) | 卡牌 **OCR**（开源） | 从卡面图取文字 |
| [Tiarait/playwright-image-translator](https://raw.githubusercontent.com/Tiarait/playwright-image-translator/refs/heads/main/README.md) | playwright 驱动的**图像/页面翻译** | 同题；待实测能否吃本地图 |
| digiKam [OCR Text Converter](https://docs.digikam.org/en/post_processing/ocrtext_converter.html) | 桌面软件批量图 OCR | 本机已有 digiKam 时可零成本 |

### 9.4 落地顺序（⏸ **第 1、2 步不急**；2026-10-13 更新）

1. ~~用 `tts-editor` 交叉验证我们手写的客户端~~ **已作废** ⇒ §9.5（项目已归档、无许可证：既没验证价值，也没可抄的代码）；
2. **外文 mod → 中文**：**接口与部署方案已独立成文 ⇒ `I18N.md`**（仓库只出"抽文本 / 写回"两侧 ＋ 一个 **TSV 契约**；翻译引擎挂 §9.3 那些现成件，⛔ **不内置任何引擎**）；
3. 其余按需。

### 9.5 读 `tts-editor` 的**实际收获**（2026-10-12 查证）

1. ⛔ **它已经死了**：原版 `matanlurey/tts-editor` **`archived: true`**、`pushed_at` = **2023-02**；`rolandostar` 那个只是 2022 年的 fork（0 star / 0 issue）⇒ **不能当依赖**。（§9.1 那行已按此改正。）
2. ⚠️ **没有许可证**（GitHub API `license: null`）⇒ 依许可**只能读思路、不能拿代码** —— 将来"贡献开源"时要守住这条。
3. ✅ **出站消息面我们并不缺**：它列 4 种（GetScripts / SaveAndPlay / CustomMessage / ExecuteLua），而 `tts\tts_api.ps1` 的文件头写着**同一张表**（`0=GetScripts 1=SaveAndPlay 2=CustomMessage 3=ExecuteLua`），且 `messageID 1` 真用在"装 Global 脚本"上 ⇒ 我们与官方 API 面**对齐**。
4. ⭐ **真正的收获在"入站"**：它把 8 种入站消息做成**事件**（`once('…')`）：`pushingNewObject` · **`loadingANewGame`** · `printDebugMessage` · `errorMessage` · `customMessage` · `returnMessage` · **`gameSaved`** · `objectCreated`。
   我们只消费"命令回执"（messageID 2/3/4），**从没订阅 `loadingANewGame` / `gameSaved`** ⇒ 这正是 2026-10-12 那个坑的根：**载入存档会冲掉 tracker 位置，而我们只能事后从 `turn_side` 的异常里猜**。
   ⇒ **可行动的改进**：桥接是 Global 脚本，**拿得到 `onLoad`/`onSave` 回调** ⇒ 在里面 `sendExternalMessage` 一条"刚被载入 / 刚被保存" ⇒ hub / 轮询器**立刻知道"回合归属已被重置、必须先校准"**，从"事后猜"变成"事前知道"。**已登记为 `HANDOFF.md` §4 第 10 条待办。**
5. ✅ **它自带的 `TTSApiBackend`**（TTS 服务端桩）与我们自写的桩（`tests\gen_bridge_primitives.lua` ＋ `tools\verify_f8.js`）**同构** ⇒ 旁证这条离线测试路线没走偏；它的桩面还可当"TTS 接口清单"参考。
