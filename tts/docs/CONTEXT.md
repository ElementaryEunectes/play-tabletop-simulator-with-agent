# CONTEXT.md —— 上下文注入与隔离（DSH 机制 + 本项目落地）

> 2026-10-08 从 `HANDOFF.md` §8 拆出来的：**每个请求都在为注入付钱**，所以这份要单独维护、单独查。
> 机制的**可版本化源**在 `HARNESS_HOME_AGENTS.template.md` 的文件头（那段不注入）；
> **回归测试**是 `tts\tests\test_agents_hygiene.ps1`（体积 / 承载性指针 / 隐私 / 漂移四项）。

---

## §8 上下文注入与隔离（DSH 的**实际**规则，2026-10-08 读源码确认）

> 源码：`@deepseek-ai/dsh-agent-instructions/lib/index.js`。**每次请求都注入**，所以这是本项目的"固定税"。

**注入什么**（按顺序）：
1. `$DSH_HOME\AGENTS.md` —— **用户全局**；文件名是**常量**，只要存在就第一个加进来
2. **项目链**：从**项目根**（`.git` 标记）**逐级到工作目录**，每级找 `AGENTS.md`/`CLAUDE.md`，再找 `AGENTS.local.md`/`CLAUDE.local.md`
3. 去重只有两种：**绝对路径**去重（同一份文件不会算两次）＋ **同目录内**去掉 trim 后内容相同的兄弟文件 ——
   源码原话：**跨目录即使内容完全相同也绝不合并**
4. 最后按**字节预算**渲染（超预算时先丢"更宽泛的"，即离项目根更远的）

**能用来"隔离"的旋钮**（`agent-instructions` 插件配置，默认值）：

| 旋钮 | 默认 | 用途 |
|---|---|---|
| `projectRootMarkers` | `['.git']` | 决定"项目根"在哪 ⇒ 决定链从哪开始 |
| `instructionFileCandidates` | `['AGENTS.md','CLAUDE.md']` | 只认一个名字就改这里（想彻底不读 `CLAUDE.md`） |
| `localInstructionFileCandidates` | `['AGENTS.local.md','CLAUDE.local.md']` | **机器专属 overlay**：不进仓库（**已 gitignore**）、**不参与去重**、叠加在最上面 |
| `maxBytes` | 由 harness 给 | 预算。⚠️ **别拿它当隔离手段** —— 它只会**截断**，会静默丢规则 |

⛔ **这个版本没有"忽略用户全局那份"的开关** —— `USER_GLOBAL_FILE = "AGENTS.md"` 是常量，存在就一定先加。
⇒ 要让全局那份不参与注入，**只有两条**：① `$DSH_HOME` 里没有 `AGENTS.md`；② **把 `DSH_HOME` 钉到本仓库根**（`start-agent.ps1` 就是这么做的）——
此时全局槽与项目槽指向**同一个绝对路径** ⇒ 按路径去重成**一份**（实测：2960 + 3925 = 6885 B/请求 → 2960 B）。
⚠️ 代价：`DSH_HOME` 同时是 harness 的家（sessions/凭据/profiles）⇒ **本机**要搬迁；**新机器**从一开始就这么配则没有代价。

**本项目的隔离姿势**：

| 内容 | 放哪 | 理由 |
|---|---|---|
| 项目专属纪律（骰子护栏/路径/param 规则） | 仓库的 `AGENTS.md` | 随 clone 走，人人相同（约 2.9 KB） |
| 机器专属（本机路径/端口/偏好） | `AGENTS.local.md` | overlay，**已 gitignore**，不会误提交进公开仓库 |
| 跨项目通用纪律 | `$DSH_HOME\AGENTS.md` | 各机器自己的事，仓库管不着 |

### 已落地（2026-10-08）—— 三个槽都真实存在了

| 槽位 | 文件 | 体积 | 谁管 |
|---|---|---|---|
| 项目 | 仓库 `AGENTS.md` | **2960 B** | git，随 clone |
| 机器 | 仓库 `AGENTS.local.md`（**gitignore**） | **1048 B** | 本机手写（换机器就不一样的事实） |
| 通用 | `$DSH_HOME\AGENTS.md` | **2924 B** | **源在仓库**：`tts\docs\HARNESS_HOME_AGENTS.template.md` —— 改模板 → 取其 `---` **之后的正文**覆盖过去（其余是文件头说明，不拷） |

- **每请求注入 = 2960 ＋ 1048 ＋ 2924 = 6932 B**。比最初"没隔离"的 6885 B 只多 **47 B（+1%）** —— 即"三个槽都在"几乎没多花钱。
- **2026-10-08 瘦身**：通用那份 4170 → **2924 B（−30%）**。砍的全是**解释性文字**：BOM 机制压成一句、8 条纪律各压成一行、
  删掉独立的「§5 边界」（并入文件头的 ⛔ 一行）—— **规则一条没删**。机制的完整说明（注入顺序 / 两种去重 / 预算 / 各类工作区注入什么）
  移进**模板头部**，那部分**不参与注入**。⇒ 通用那份的"知识"与"成本"从此可以分开维护。
- **有回归测试了**：`tts\tests\test_agents_hygiene.ps1`（**不需要 TTS，也不需要 Node**）：
  项目那份 ≤3 KB ＋ 必含 5 个承载性指针（`start-agent.ps1` / `DICETHRONE_STATE.md` / `PLAY.md` / `tts\config.ps1` / `check_ps1.ps1`）·
  **被 git 跟踪的文件里不许出现真实用户名或绝对用户路径** · `AGENTS.local.md` 必须被 gitignore 且 ≤2 KB ·
  **全局那份必须与模板正文逐字一致**（漂移检查）。它第一次跑就抓到我写进 §6.13 的真实用户名。
- ⚠️ 全局那份**在工作区之外** ⇒ 写它需要**一次提权**；而且**无法自动化**（"模板即源"是我们自己约定的，harness 不知道）。
- ⚠️ 测试会 `WARN`："全局那份比项目那份还大" —— 本项目**确实如此**（通用那份扛着 BOM/沙箱/PS 5.1/端口这些跨项目纪律），
  但它是**有用的信号**：哪天通用那份继续长胖，就该按 §1 的"边界"往下砍。

**想跨工具统一**（Cursor / Copilot / Claude Code / Codex 各读各的规则文件）⇒ 开源方案 **[rulesync](https://rulesync.dyoshikawa.com/)**（MIT）：
单一真源 → 按 target 生成各家文件、支持 project/global 两套作用域；它的支持表里**已列 DeepSeek Harness**。

### 试点结论（2026-10-08，**实测 rulesync 27.0.0**）—— 跑通了，但**建议暂不采纳**

做法：`out\rulesync_pilot\` 里放三份源 —— `00-generic.md` / `10-project.md`（都 `root: true`）＋ `90-machine.md`（`localRoot: true`），
`rulesync generate --targets agentsmd,claudecode --features rules` ⇒ 合成**单个** `AGENTS.md`（**5555 B / 77 行**），
顺序＝**文件名序**、段间空行分隔 ⇒ "通用 ＋ 项目"合并成一份这件事它做得对，`doctor` 与 `--dry-run` 也都能用。

- ⚠️ **收益来源要说清**：今天两份注入合计 **6885 B**（项目 2960 ＋ 全局 3925），试点产物 **5555 B（−19%）** ——
  但**省下来的不是 rulesync 的功劳，是我把"通用那半"写瘦了**（砍掉 §4 索引/加载机制与 §5）。
  ⇒ **不引入 rulesync 也能拿到这 19%**，只要把全局那份压瘦。
- 三条硬事实（都实测）：
  1. **rulesync 没有"DSH 用户全局"target**：global 模式只支持 Claude Code / Copilot / OpenCode
     ⇒ **`$DSH_HOME\AGENTS.md` 它生成不了**，得额外一步复制（那路径还在工作区之外 ⇒ 需提权）。
  2. **`localRoot: true` 必须配同 target 的 `root: true`**，否则直接报错：
     `localRoot: true requires a root: true rule to exist for target 'claudecode' (found in .rulesync\rules\90-machine.md)`
     ⇒ 想隔离出一份 `.local.md`，就得顺带生成那个工具的根文件。
  3. **它会往产物里塞自家样板**：`agentsmd` target 在开头插
     `# Additional Conventions Beyond the Built-in Functions` ＋ 一句英文说明（≈150 B，**每次请求都付**），并且**挪走了我们的 H1 位置**。
- **结论**：对本项目（Windows / PowerShell / 单一消费者只 DSH）⇒ **不引入**（Node 工具链 ＋ 目标样板 ＋ 复制步骤，换不到东西）。
  **但照抄它的"三份源"纪律**（就是本节上面那张表）；真要跨工具时（Cursor/Copilot/Codex）再上它。
  它最值钱的是 `generate --check`（CI 防漂移）—— 我们要的话，一条"AGENTS.md 体积上限 ＋ 必含小节"的检查就能替代。

---

## 附：各类工作区会注入什么（2026-10-08 实测）

| 工作区 cwd | 通用 | 项目 | 机器 | 每请求注入 |
|---|---|---|---|---|
| **不在任何 git 仓库里**、且该目录没有那四个候选文件（例 `~/work`；`~/.dsh` 也满足） | ✅ | ❌ | ❌ | 只有通用那份 ≈ **2924 B** |
| `…\tts-agent` 仓库根（现状，**裸起** `dsh`） | ✅ | ✅ | ✅ | 2924 ＋ 2986 ＋ 1048 ≈ **6.96 KB** |
| `…\tts-agent` ＋ 用 **`start-agent.ps1`** 起（`DSH_HOME` 钉到仓库根） | ✅ 与项目槽**同绝对路径** ⇒ 去重 | ✅ | ✅ | 2986 ＋ 1048 ≈ **4.0 KB** |
| `…\tts-agent\tts\`（从子目录起会话） | ✅ | ✅ | ✅ | 同上 —— **仓库根仍在链上** |

- ⚠️ **在仓库内永远做不到"只有通用槽"**：仓库根一定在链上 ⇒ `AGENTS.md` 与 `AGENTS.local.md` 必然注入。
- ⚠️ 放进**子目录**的 `AGENTS.md` **只在从该子目录（或其下）起会话时生效** —— 本项目永远从仓库根起会话 ⇒ 放了等于没放。
- 想要"只有通用槽"：`cd` 到一个**不在任何 git 仓库里、且自己没有 `AGENTS*` / `CLAUDE*`** 的目录再起 dsh。
  （`~/.dsh` 本身也满足条件 —— 链扫到的是与通用槽**同一绝对路径**的文件，按路径去重 —— 但它是 harness 的家，凭据与会话历史都在那儿，**不推荐**拿它当工作区。）
- 结论：**改 `AGENTS*` / 挑工作区之前先看这张表** —— 最容易误判的两件事就是"子目录能隔离"和"仓库里能只注入通用那份"。

