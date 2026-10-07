# tts\docs\ 文档索引 —— **要"还有哪些文件 / 什么在哪儿"时读这一页**

> 别翻目录、别整份读手册。每份文档顶部都有一句"什么时候读我"。
> ⚠️ **跨项目平台纪律**在 `~/.dsh\AGENTS.md`（自动注入）；**TTS 全套规则/工具/坑**在 **`TTS_RULES.md`**（做 TTS 工作时读一次）。

| 文件 | 一句话 | 何时读 | 变更频率 |
|---|---|---|---|
| **`TTS_RULES.md`** | **TTS 通用规则**：跟人怎么配合 · 隐藏信息纪律 · 工具地图 · 一回合循环 · 按钮定案 · TTS 特有的坑 · 换局流程 | **开工前读一次** | 低 |
| `DICETHRONE_STATE.md` | ⭐ **王权骰铸 = 唯一真源**：HP/CP · 状态 token · 待办 · guid | **每回合（与 PLAY 一起，就这两份）** | **每回合** |
| `PLAY.md` | **每局随身卡**：回合步骤 · 控制台动词（含 ⭐`turn` 一条命令开局）· 哨兵/STATE 约定 | **每回合** | 换局 |
| **`USER_GUIDE.md`** | **人怎么用**：开局 · 你只做两件事 · AI 何时请你帮忙 · 在哪说话 · 常见问题 · 什么会动桌面/存档 | 第一次用 / 拿给玩家看 | 低 |
| `CURRENT.md` | **现在在玩哪个游戏** + 指向哪份 STATE / FLOW | 需要时（1 行） | 换局 |
| `DICETHRONE_FLOW.md` | 王权骰铸规则：阶段 · 投掷/防御 · **行动牌与响应窗口** · 伤害类型表 · 技能表 · 骰面映射 | 按需查小节 | 学到新规则时 |
| `BOOTSTRAP.md` | **冷启动 / 换局 / 换模组**的唯一工作流（三种情形） | 换局时 | 低 |
| `TTS_WORKFLOW.md` | 跨游戏技术手册（索引/识别/几何/工具/PowerShell 陷阱）· **按节取用** | 查技术细节 | 低 |
| `PRIOR_ART.md` | 二手调研与先例（**冻结，别重搜**） | 查先例 | 冻结 |
| `archive\` | **过期留档：旧简报 ×4 · 旧 STATE · 游城拓荒全部文档（FLOW/REF）· 旧 init 产物** —— **不要读** | 永不 | 冻结 |
| `..\SCRIPTS.md` | **`tts\*.ps1` 脚本清单**（按使用频率分类，含"休眠但别删"的说明） | 找脚本/清理时 | 低 |

**目录约定**（保持干净 = 省 token）
- `tts\*.ps1` = **现役工具**；**清单与用途见 `tts\SCRIPTS.md`**；死的、一次性的、实验性的一律进 `archive\tts-legacy\`。
- `tts\tests\` = **离线自测（不需要 TTS、不需要存档）**：`test_diff_index.ps1`（桩冒充 `live_index.ps1` ＋ 合成 fixture）·
  `test_param_backfill.ps1`（每个 `''` 默认值必须被回填或判空）。**改完脚本先跑它们**，比开游戏试便宜得多。
- `tts\lua\` = TTS 模组的**全局 Lua**（`dsh_global.lua` = 桥接本体；`install_save2.ps1` 依赖它，**别动**）。
  `tts\validate_lua.js` = 改 Lua 前的校验器。
- `cache\` = **产物**（可重建）：`front.txt` / `chan.txt`（哨兵心跳）· `dicethrone_rules.json` / `dicethrone_cards.md`（游戏数据）·
  `live_index.csv` / `baseline.csv`（快照）· `hidden_zones.csv`（隐藏区规则）。
  `cache\_artifacts\`（旧截图/裁图）· `cache\_legacy_nomadcity\`（上一局的产物）—— **别读，别改**。
- `archive\out_legacy\` = 旧的一次性分析图。`saves_backup_*\` = 存档备份（**写存档走 `install_save2.ps1`**）。
