# INJECTION.md —— 你的指令文件**怎么被注入**、要花多少钱

> **什么时候读我**：**安装 / 换机器时**（决定三份指令文件放哪）；或改了 `AGENTS.md` / `AGENTS.local.md`，想算清成本时。
> 机制来自 DSH 源码（2026-10-08 读码确认），**每条都有实测数字**。
> 装完用 `tts\doctor.ps1` 复核（第 3 段逐槽列出字节数）。

## 1. 三个槽（DSH **每个请求**都注入它们）

| 槽 | 路径 | 内容 | 进仓库？ |
|---|---|---|---|
| **用户全局** | `$DSH_HOME\AGENTS.md` —— 文件名是**常量**，**存在就第一个加**，**与 cwd 无关** | 跨项目纪律 | ❌ 不属于任何仓库 |
| **项目链** | **项目根 → cwd 的每一级**找 `AGENTS.md` / `CLAUDE.md`（项目根 = 从 cwd 向上第一个含 `.git` 的目录；一个都没有时 = cwd 自身） | 项目纪律 | ✅ |
| **本机 overlay** | 与上面**同级目录**里的 `AGENTS.local.md` / `CLAUDE.local.md` | 只讲"这台机器" | ❌（`.gitignore` 已挡 `*.local.md`） |

## 2. 三条硬规则（决定"会不会重复付费"）

1. **绝对路径去重**：同一份文件不会算两次 ⇒ 若全局那份与项目那份是**同一个绝对路径**，只付一次。
2. **同目录内**、去掉首尾空白后内容相同的兄弟文件（`AGENTS.md` 与 `CLAUDE.md`）算一份；**跨目录即使内容完全一致也绝不合并**。
3. **字节预算**：超预算时**先丢"更宽泛的"**（离 cwd 更远的） ⇒ 先丢**全局那份**，再丢外层项目文件。

⚠️ **没有"忽略全局那份"的开关**（文件名是常量，且与 cwd 无关）⇒ 要它不参与注入只有三条路：**那个文件不存在** · 让它与项目那份**同绝对路径** · **给该项目一个专属 profile，把指令插件的 `dshHome` 指到空目录**（⇒ **§4 方案 A′**）。前两条都是**全局性**的；**只有 profile 级补丁能"按项目"屏蔽**。

## 3. 成本（实测）

| 配置 | 每请求注入 | 何时值得 |
|---|---|---|
| **默认（本项目当前）**：机器上放一份全局的 | **全局 ＋ 项目 ＋ overlay**（实测 3,950 ＋ 3,518 ＋ 2,299 = **9,767 B**） | 多项目**共享同一份纪律**时值得（本机现在就是这样） |
| ⭐ **本项目发布时**（**方案 A′**）：该项目专属 profile 把全局槽指空 | **项目 ＋ overlay**（实测 **5,817 B**） | 想"全局留给别的项目、本项目不付这份钱"⇒ 见 §4 方案 A′（**不必删全局文件**） |
| 把 `$DSH_HOME` **钉到本仓库根** | 与上一行相同（两槽同绝对路径 ⇒ 去重成一份） | ⚠️ 代价：harness 的家（`sessions\` · 凭据 · `profiles\`）会落进**项目目录**；已有状态的机器要迁移 |

## 4. 安装时照这个做

1. **全局那份"放不放"是一个选择，不是默认答案**：放 ⇒ 每个项目都注入它（本机当前如此）；**只想让某个项目不注入 ⇒ 别删它，用 §4 方案 A′**。⚠️ 全局槽的路径是 `$DSH_HOME\AGENTS.md`（**常量名**），与 cwd 无关。
2. 本项目要用的通用纪律，按**"出错是否静默"**分流：
   - **静默出错**的（例：给函数起名撞了 PowerShell 内置别名 ⇒ 真删文件）⇒ 放 **`AGENTS.local.md`**（overlay，每请求注入、不进仓库）；
   - **有症状**的（跑脚本报错、乱码、写不进去）⇒ 放**仓库里的跟踪文档**（`tts\docs\MAINTENANCE.md` §0 · `CONTRIBUTING.md` §4），**按需读、不占每请求预算**。
3. **本机专属**的东西（绝对路径、账号、端口）**只能**进 `AGENTS.local.md`：跟踪文件里不许出现用户名 / 绝对用户路径（`tts\tests\test_agents_hygiene.ps1` 会强制检查）。
4. 本项目给两个注入文件都设了上限并由测试强制：`AGENTS.md` ≤ 3,840 B · `AGENTS.local.md` ≤ 4,096 B。装完跑 `tts\doctor.ps1` 看实测值。
5. 跨项目那份的**可版本化源**是模板文件（`---` 以下正文＝要拷过去的内容）；本项目把平台层放在 harness home 的 `platform\` 目录（不在仓库里），clone 下来的人没有它也不影响使用。

### 方案 A′ —— **保留全局纪律 ＋ 按项目屏蔽**（本项目发布时走这条）

**要解决什么**：全局那份是**跨项目共享**的（删了别的项目也没了），但**某一个项目**可能不想付它的字节。

**机制**：DSH 的 profile 是一叠**补丁层**（`package.json` 的 `dsh.profile.bundles` → `cordis.patch.yml` → 命令行的 `--patch`）。
用户全局指令文件的路径 = **指令插件**的 `config.dshHome` ＋ **常量**文件名 `AGENTS.md`（源码：`const userGlobal = join(config.dshHome, USER_GLOBAL_FILE)`）
⇒ 在该项目的 profile 里**把 `dshHome` 指到一个空目录**，就只有那个 profile 的全局槽为空。
⭐ **这是"按项目屏蔽全局槽"唯一能做到的机制**（另外两条路都作用于整台机器，见 §2）。

**目录结构**（`$DSH_HOME\profiles\<项目名>\`；`<项目名>` 就是 `--profile` 那个名字）：

```text
profiles\tts-agent\
  package.json          # name + dsh.profile.bundles（照抄默认 profile：dsh-base / dsh-web-app / …）
  cordis.yml            # profile 根：空列表 []（树是"叠加"出来的，别改它）
  cordis.patch.yml      # ⭐ 本项目那一层补丁（唯一需要改的文件）
  pnpm-workspace.yaml   # 该 profile 有自己的依赖树 ⇒ node_modules\ 必须装
  no-global\            # 空目录，只为把 dshHome 指过去
  node_modules\         # ⚠️ 缺了它 bundle 解析不了（见下面第 ② 步）
```

`cordis.patch.yml`（本项目 `~\.dsh\profiles\tts-agent\` 里就是这份）：

```yaml
- id: agent-instructions
  config:
    maxBytes: 65536                       # README 的必填项显式写全，免得"覆盖式 config"丢别的字段
    dshHome: <空的 no-global 目录的绝对路径>   # 全局指令文件 = dshHome + 常量名 AGENTS.md ⇒ 空槽
```

**三步**（2026-10-09 实测）：

```powershell
dsh tts-agent --from-default-profile web     # ① 从默认 profile 拷一份骨架（或手工建上面那 4 个文件）
dsh plugin --profile tts-agent install       # ② ⚠️ 必须有：不装 ⇒ `--dump-config` 直接退 1，报
                                             #    "cannot resolve profile bundle dsh-web-launcher"
dsh --profile tts-agent                      # ③ 启动（`dsh tts-agent` 是同一件事的简写）
```

- ✅ **只有这个 profile** 的全局槽为空；默认 profile（`web`）与别的项目**照旧注入** ⇒ "全局纪律保留 ＋ 本项目可选屏蔽"。
- ✅ **不搬 harness 家**（会话/凭据仍在 `~\.dsh`）、**不用 junction**（避开 §5 的坑）。
- ⛔ **语法别写错**：`dsh [--profile] <profile名> [app 参数…]` ⇒ **`dsh tts-agent web` 是错的** —— `web` 会被当成 **app 的参数**递进去；`dsh web` 只是 `dsh --profile web` 的简写。
- 🧰 **本项目不用手打**：`start-agent.ps1` 里的一行 `$ProjectDshProfile`（命令行可 `-DshProfile tts-agent`）就会拼出第 ③ 条，并替你检查 profile **在不在**、**装没装**（缺 `node_modules` 时直接给出第 ② 条命令）；`start.cmd` 的参数原样转发。

## 5. ⛔ 两个别做（都有实测代价）

- **别把 `DSH_HOME` 指向"链接拼出来的目录"**（junction / symlink 农场）：注入目标能达成，但 Windows 沙箱启动子进程时会崩 —— `0xc0000142`（DLL 初始化失败），且抓取输出会**静默变空**（`$LASTEXITCODE` 也为空 ⇒ 测试全哑，看起来像"跑过了"）。用**真目录**。
- **别把机器事实写进跟踪文件**（用户名 / 绝对路径）：用 `.local.md`；开源发布前还要按 `OPENSOURCE-TEMP` 标记清理一次（见 `CONTRIBUTING.md`）。
