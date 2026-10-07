# RULEBOOK.md —— 官方规则书：**在哪 · 怎么拿 · 每页是什么**

> 来源：**它就躺在存档里**（PRIOR_ART §1.1 的"存档 = 结构化元数据宝库"技巧落地）。
> 用途：规则/数值有争议时**先查这里**，别靠记忆、别猜。

## 在哪

| | |
|---|---|
| 物件 guid | `0f4dfd` |
| 名称 | `Custom_PDF` · nick = **「规则书（中2.3英2.4版本）」** |
| URL | `https://steamusercontent-a.akamaihd.net/ugc/2009199444108534222/153A17B3EB4FAF6AAE0BD1B1027E9E812A1974D9/` |
| 体量 | **9,117,462 B**（真 PDF，`%PDF-`）· **15 页** · **图片型、无文本层**（全篇只 351 字符） |

⚠️ 它是**基础规则 ＋ 枪手（Gunslinger）示例页**，**不含**月精灵/猩红女巫的卡面数值。
⇒ **英雄专属数值**（`长弓 III` 是 5/7/9 还是 4/5/7 之类）仍以**桌上卡面**为准（`tts\crop_zoom.ps1` 裁图读）。

## 怎么拿（三步，脚本都在仓库里）

```powershell
tts\obj_index.ps1                                    # 1. 从存档取 URL（src=CustomPDF.PDFUrl ⇒ pdfurl 列）
node out\_selftest\fetch_pdf.js <URL> cache\rulebook_dicethrone.pdf                  # 2. 下载
node out\pdftool\pdf_images.js cache\rulebook_dicethrone.pdf cache\rulebook_pages    # 3. 抽整页图（15 张 2593x1547）
```

- ⚠️ **为什么必须用 Node 下载**：沙箱里 `curl.exe` 与 `Invoke-WebRequest` 都报 TLS 凭证错
  （`schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS`）；**Node 自带 TLS 栈**所以只有它能成（`npm` 能联网就是同一个道理）。
- ⚠️ **别指望抽文本**：`pdf-parse` 的结果是 **15 页共 351 字符**（图片型）⇒ 直接看**整页图**（读图工具），或用 `crop_zoom.ps1` 裁局部放大。
- 产物全在 `cache\`（**不进仓库**）：`rulebook_dicethrone.pdf` · `rulebook_pages\p01..p15.jpg` · `rulebook_index.png`（15 页缩略拼图，**一眼定位**）。

## 每页是什么（2026-10-08 从缩略拼图读出的目录）

| 页 | 内容 | 我们要拿它查什么 |
|---|---|---|
| p01 | 封面 · 游戏总览 · 胜利条件 · 致谢 · 术语 | 术语定义 |
| p02 | 英雄面板/卡面示例（枪手）· 生命值转盘 · 战斗点数 | 面板读法 |
| p03 | **游戏设置**（8 步；起始手牌 4 张、起始 CP） | 开局 / 复位 |
| p04 | **回合阶段**（收入 · …）· 生命值与最大生命值 | 阶段顺序 |
| p05 | **状态效果图标表** | ⭐ 爆裂 / 缠绕 / 致盲 / 闪避 / 操控概率 的官方定义 |
| p06 | 状态效果（续）· 同伴 · 游戏流程图 | token 叠加 / 清除时机 |
| p07 | **英雄升级 · 打出升级卡牌 · 行动卡牌** | ⭐ 响应窗口里到底能打什么 |
| p08 | 主要阶段 · 行动卡牌 · **结算文本** · **防御** · 「缠绕」 | ⭐ 防御判定与结算措辞 |
| p09 | **伤害类型表**（真实伤害 / 不可防御 / 防御 / 状态效果…） | ⭐ 与 `DICETHRONE_FLOW.md §4.3` 对表 |
| p10 | **攻击修正** · 加入游戏（其他模式） | 修正怎么加 |
| p11 | **回合详解**（各阶段逐步） | ⭐ 收尾阶段 / 挂账时机 |
| p12 | 回合详解（续）· **最终总计伤害** | 伤害结算顺序 |
| p13 | 最终总计伤害（3 步）· 游戏结束 | 结算三步 |
| p14 | 时停冲突 · 中文版致谢 | 边界情况 |
| p15 | **速查表** | 速查 |

（目录是从 `cache\rulebook_index.png` 那张缩略拼图读出来的；**正文细节要哪页就看哪页的 `pXX.jpg`**。）
