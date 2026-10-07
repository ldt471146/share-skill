---
name: paper-finder
description: 当用户给出题目或关键词，要求在知网找论文、复制知网导出引用、整理参考文献或保存论文页面截图时使用；不用于下载全文或精读论文。
---

# 知网找论文、导出引用和截图

按用户给出的主题、数量、年份、语种和格式执行。四步：检索、锁定记录、导出引用、按需截图。默认单路操作真实 Chrome（agent-browser-cli），不写综述、不下载全文、不做出版社交叉核验、不加额外报告；用户另有要求时再做。

脚本一律用绝对路径调用（执行目录是工作区，不是 skill 目录），下面记作 `$S`：

```powershell
$S = "$env:USERPROFILE\.agents\skills\paper-finder\scripts"   # .codex\skills\paper-finder 另有一份副本，改动要同步
```

调用约定（本机实测）：`exec --tab <id> --file <脚本>` 的结果在 `result.js_return`；`tabs` 的结果在 `result.metadata.tabs[]`（字段 `tab_id` / `url`）。形状不符先跑 `agent-browser-cli tabs | ConvertFrom-Json | ConvertTo-Json -Depth 6` 看真实结构。JS 助手脚本含顶层 `return`，只能走 `--file`，不能内联。

## 两种检索模式

| 模式 | 触发 | 入口 |
|------|------|------|
| 精确找（1 篇） | 给了题名或 DOI | `pwsh -File "$S\search-cnki.ps1" -Database Chinese -Field Title -Query "<题名>"`，取输出的 `tab_id:`，再点该行「引用」 |
| 主题批量找（N 篇） | 给了主题 + 篇数/年份（“找十篇文旅系统近三年”） | 下两节：关键词检索 + 左栏筛选 + 批量导出 |

- `-Database Chinese` 走 `kns8s...?kw=`，**只按关键词检索**，`-Field` 只对 `-Database Foreign`（scholar.cnki.net 外文总库）生效；`-Query` 传原始文本，脚本内部做 URL 编码。
- 英文若中文入口无结果，改用 `-Database Foreign`，不把中文页无结果当成知网未收录。
- 脚本输出的 `tab_id` 就是后续所有 `--tab` 的值。

## 主题批量检索

左栏结构固定：`#divGroup dl`，每块 `dt.tit`（主题／来源类别／学科／研究层次／年度／文献类型）+ `dd`（选项懒加载）。左栏用普通 JS click 即可（与翻页、导出菜单不同）：

```js
// 展开某块并列出选项（「文献类型」可换成 年度 等）
const t=[...document.querySelectorAll('#divGroup dt.tit')].find(d=>d.textContent.includes('文献类型'));
t.click(); return [...t.parentElement.querySelectorAll('dd li')].map(li=>li.textContent.trim()).join(' | ');
// 勾选其中一个选项
[...t.parentElement.querySelectorAll('dd li')].find(li=>li.textContent.includes('研究论文')).querySelector('input[type=checkbox]').click();
```

- 选项读出来是空的，就是没展开，先点 `dt.tit`；选项文案自带条数，如 `研究论文 (158)`、`2025年 (36)`。
- 文献类型选 `研究论文`（`资讯` 是报纸新闻稿；用户要“论文”就排除）。
- 年度：近 N 年 = 当前年起往前 N 个年份（2026-10 的“近三年”= 2024／2025／2026），逐年在年度块里勾选，勾选即生效；口径不确定先问一句。
- 进度看 `#countPageDiv`（含“共找到 N 条结果”）和 `#selectCount`。
- 取条目：`agent-browser-cli exec --tab <tab_id> --file "$S\cnki-rows.js"` 一次返回整页 20 条的 题名/作者/来源/日期/类型，不要 snapshot 整页。
- 翻页：数字页码链接 JS click 无效，用 `上一页`／`下一页`（JS click 可用）。勾选跨页保留，但 `cnki-select.js` 只认当前页，所以**每翻一页重跑一次勾选**：把上一轮返回的 `missing` 作为下一轮 `__CNKI_WANT`，直到 `missing` 为空或已够 N 条。

## 批量导出引用

1. 设目标题名并勾选，返回的 `selected` 对着 `#selectCount` 核一下：

```powershell
agent-browser-cli exec --tab <tab_id> 'window.__CNKI_WANT=["题名子串A","题名子串B"]; "ok"'
agent-browser-cli exec --tab <tab_id> --file "$S\cnki-select.js"
```

2. 导出菜单是纯 hover，JS `.click()` 无效，必须走 CDP 真实鼠标事件（mouseMoved→mousePressed→mouseReleased，坐标由 `getBoundingClientRect()` 取）。脚本已封装，一条命令走完 导出与分析 → 导出文献 → GB/T 7714-2025 并回报新标签：

```powershell
pwsh -File "$S\cnki-export.ps1" -Tab <tab_id>     # → export_tab: / export_url:
```

3. 导出页是 `kns.cnki.net/dm8/manage/export.html`，引用正文在 `#result`。先设过滤词，再在 **export_tab** 上读：

```powershell
agent-browser-cli exec --tab <export_tab> 'window.__CNKI_FILTER="文旅"; "ok"'
agent-browser-cli exec --tab <export_tab> --file "$S\cnki-export-read.js"   # → {total, kept, blocks}
```

- ⚠️ 导出的是**当前全部已选**：会话里残留的旧勾选会一起导出（实测混进过 23 条无关旧记录，导出页条数也可能与 `#selectCount` 不一致）。**按题名过滤出用户要的篇目，不要按条数判断**；`a.btn-clearall`（清除）实测无效，别依赖它。
- `blocks` 是带展示空格的原文，落成 UTF-8 文件再清洗：

```powershell
$d = ((agent-browser-cli exec --tab <export_tab> --file "$S\cnki-export-read.js" | Out-String | ConvertFrom-Json).result.js_return | ConvertFrom-Json)
$d.blocks -join "`n" | Set-Content -LiteralPath raw.txt -Encoding UTF8
```

- 批量模式（≥2 篇）不要逐篇点「引用」弹窗（10 篇 = 20 次往返）；单篇精确找才用那一列。

## 引用文本要清空格（最易错）

知网页面上的引文带展示用空格（`, ` `[J]. ` `: ` `[C]// `），官方 GB/T 7714-2025 和剪贴板版本没有。清洗规则：**只删半角标点（`.,:;()[]/`）相邻的空格**，其余字符（全角括号、`、`、`——`、`’`、英文词间空格、中文）一律不动。用脚本，不手工重排：

```powershell
pwsh -File "$S\clean-citation.ps1" -Path raw.txt -OutFile clean.txt   # 或 -Text "单条引用"
```

用文件或 `-Text` 传中文，别用管道（子进程管道按控制台代码页编码，中文会乱码）。清洗会把 `[5] ` 一并压成 `[5]`，交付时按用户要求重新排（年份倒序、连续编号）。

`tests/clean-citation.tests.ps1` 是该脚本的回归用例（含用户确认过的期望行，跑法 `pwsh -NoProfile -File "$S\..\tests\clean-citation.tests.ps1"`）；改脚本先跑它。

## 截图

点结果页的题名链接进详情页（`agent-browser-cli click --tab <tab_id> '<题名所在行的 a>'`，新标签从 `tabs` 里认），在详情页标签上跑
`agent-browser-cli screenshot --tab <详情tab> --full-page --out <路径>`。只目视检查第一张是否显示知网标识、题名和作者；其余以命令成功返回和文件路径为准，不逐张复检。

## 实测陷阱（踩过的，别重犯）

- **检索词别混中英**：`kw` 是分词 AND。`图书管理系统 Spring` / `Spring Boot 图书管理系统` 这类中英混排会退化成近似全表或只剩 1～3 条；`题名` 字段（URL 加 `&korder=TI`）更精确，但中英混排同样靠不住。要“Spring Boot 主题”的论文，就分别用 `Spring`、`SpringBoot`、`SSM`、`Vue`、`Java` 等词各跑一次题名检索（每次都能拿到 1～6 条精确命中），再合并挑选，比死磕一个复合查询快得多。
- **导出页的列表是滚动懒加载**：刚打开只渲染 20 条，`window.scrollTo(0, document.body.scrollHeight)` 反复滚到底（约 5～14 次，直到 `#result` 的条数不再增长）才会把全部已选渲染出来（实测 20 → 58 条）。`.search-page` 那个 `1 / 10` 翻页控件是死的（元素 0 尺寸），别去点它。
- **条目的「引用」弹窗（`a.icon-quote`）在本机不渲染**（点了没有任何 dialog / iframe / 新标签），单篇引用要拿文本时不要指望它，走批量导出。
- **导出页 `dm8/manage/export.html` 可以直接开**：不用点 hover 菜单，`agent-browser-cli open --window --focus "https://kns.cnki.net/dm8/manage/export.html?language=CHS&uniplatform=NZKPT"` 就能拿到当前已选的全部引用（默认就是 GB/T 7714-2025），比 CDP 点菜单稳得多。
- **导出页只渲染前 20 条**（滚动后可见全部，见上）；**多个标签页可以累积勾选**（已选是会话级的，跨标签、跨检索都在同一个列表里），所以分几次检索、分几个标签勾选，最后统一导出即可。
- **CDP 鼠标事件要求标签可见**：窗口最小化/标签在后台时 `window.innerHeight` 会返回 0，菜单点了不展开。先 `agent-browser-cli open --window --focus <url>` 把窗口拉到前台。
- **坐标读取脚本里不要滚动页面**：hover 菜单一旦被 `scrollTo` 打断就收起，后续坐标全变 0/NaN。
- **批量条目的「引用」是 `a.icon-quote`（无文字）**，不是文本链接；单篇引用弹窗走它。
- **exec 会 15s 超时**：导出页这种重页面报 `No response data in 15s` 是正常的，重试 1～3 次多半能拿到结果。

## 极速模式（测过的提速手段）

按收益排序，全部实测：

1. **冷门主题补技术类论文**（用户教的招）：`Spring Boot` 系统/平台这类题目本身文献少（`校园外卖 + SpringBoot` 题名命中 0），但题名 `Spring Boot 框架` / `Spring Boot 技术` 一次探针就有 20 条命中。系统类凑不满 10 篇时，用 2～3 篇技术类论文补齐——省掉 5～8 次探针，单这一项就能把检索阶段从 50 s 压到 10 s。
2. **并行开探针标签**：`agent-browser-cli open` 循环里**不要逐个 sleep**，一次开 2～4 个，统一等 7 s，再逐个读（每个 1～2 s）。实测 2 个探针 8 s、3 个 9 s；顺序开要 12～18 s。
3. **一个 PowerShell 调用串完整个链路**：探针 → 勾选 → 直开 dm8 → 读 → 清洗写文件，中间不要分多次调用（每次调用固定开销 2～5 s）。实测「勾选 10 篇」只要 3 s。
4. **导出用一条命令**：`pwsh -File scripts/cnki-export-all.ps1 -Tab <export_tab> -Filter "<关键词>"`，内部已含滚动加载循环 + dump + 清洗并直接打印引用。
5. **⚠️ 已选积压是硬墙，每轮开始先读 `#selectCount`，交付后立刻清空**：导出页只渲染「最新 20 条」，滚动懒加载能涨到 60～80 条但**不稳定**（实测 20→40→80 成功过，也出现过 20→60 就卡住；页面 JS 一卡，exec 就成片 `No response data in 15s`）。已选一旦积压（实测积到 98 条），**老文献（2020 年以前）永远进不了渲染窗口，引用就取不到**。
   - **输出完就清，一条命令（实测 10 → 0 约 10 s）**：

     ```powershell
     pwsh -File "$S\cnki-clear-selection.ps1" -Tab <任一结果页 tab_id>
     ```

     原理：`a.btn-clearall`（清除）是死的（JS click / CDP 真实鼠标 / mousedown+mouseup / 找确认层，四种点法 `#selectCount` 纹丝不动），已选实际存在 localStorage 的 `FileNameSNZKPT` / `batchNZKPT` / `SelectFileNameSNZKPT` / `filenameIndexNZKPT`，删掉这几个键再刷新才归零。
   - 清完顺手关掉本轮开的结果页标签：多个结果页各自持有一份内存副本，你继续在别处勾选时它们会把旧列表写回 localStorage（今天因此丢过一次勾选）。
   - 纪律：每轮控制在**已选 ≤20**，选完立刻导出；发现积压立刻停下，请用户手动点一次「清除」或换会话，别硬耗（本次为这条白烧 30 min）。
6. **别指望单篇路径**：条目的 `a.icon-quote`（引用）弹窗在本机不渲染；结果页标题链接常被底部浮动批量条盖住（`getBoundingClientRect().top == 0`，`elementFromPoint` 命中不到），要么先 `window.scrollBy(0,-150)` 再校验命中点。
7. **exec 的 15 s 窗口**：重页面（dm8、结果页首次加载）会报 `No response data in 15s`，重试 1～3 次即可；不要在 exec 里跑长 async（`await` 循环会被 15 s 截断，返回 NaN）。

现实下限：10 篇引用 **约 40～75 s**（探针 8 s + 勾选 3 s + 导出 40～55 s + 清洗 3 s）。再快只能靠少跑几篇或复用已有导出页。

## 例子：一轮 66 秒的标准节奏（照抄这个）

任务：给「Spring Boot 二手车交易」找 10 篇引用。**不用很精确，凑够篇数、能溯源就行。**

```powershell
# ① 并行开探针（不逐个 sleep）——中文词组 + 单个英文词，一次开 8 个，13 s
#    二手车 设计与实现 / 二手车 Web / 二手车 Java / 二手车 网站 /
#    二手车 交易 平台 设计 / 二手车 管理系统 / 二手车 推荐系统 / 二手车 交易 系统
$u = "https://kns.cnki.net/kns8s/defaultresult/index?korder=TI&kw=<URL编码>"
$t = (agent-browser-cli open $u | ConvertFrom-Json).result.opened_tab_id
# 全开完再 Start-Sleep 8，然后逐个 exec --file cnki-rows.js 读题名/来源/日期/类型

# ② 定题：框架词命中少就别死磕——题名 `二手车 SpringBoot / SSM / Vue` 全是 0 命中，
#    于是用「基于Web / 基于Java EE / 设计与实现 / 平台设计」这类系统开发论文补齐。

# ③ 勾选：每个标签先设目标，再跑选择脚本（跨标签累计，selected 要等于 10）
agent-browser-cli exec --tab <tab> 'window.__CNKI_WANT=["题名子串A","题名子串B"]; "ok"'
agent-browser-cli exec --tab <tab> --file "$S\cnki-select.js"      # 10 s 搞定 10 篇

# ④ 导出：直开 dm8（已选 ≤20，不用滚动），读 + 清洗
pwsh -File "$S\cnki-export-all.ps1" -Tab <export_tab> -Filter "二手车"

# ⑤ 收尾（固定动作）：清空已选 → 关掉本轮标签
pwsh -File "$S\cnki-clear-selection.ps1" -Tab <任一结果页>
agent-browser-cli close --tab <本轮自己开的每个 tab>
```

实测：探针 13 s ｜勾选 10 s ｜导出+清洗 ~40 s ｜收尾 ~10 s → **总计 66 s，输出 10 条引用，已选归零。**

反面教材（同一天，30 分钟）：上一轮没清已选，积压到 98 条 → 导出页最新 20 条的窗口把 2014–2020 年的老文献全挡在外面，`清除` 按钮又点不动，只能靠清 localStorage 才救回来。

## 外文库（英文文献）检索与导出

外文库 = `scholar.cnki.net`（同一份登录态，但**另一个站点、另一套已选列表**，和 kns 的已选互不影响）。

**检索**（URL 直开，别用界面）：
`https://scholar.cnki.net/homeSearch?sw=TI&text=题名&sw-input=<URL编码>&operator=TOPRANK`
（`sw=TI` 题名；也可 `SUW` 主题词。）

- ⚠️ **多词题名普遍「无数据」**：`library management system Spring Boot`、`spring boot library system`、`library system spring boot` 全空；放单组词 `library management system` 就有 884 条。**英文也用「短词组」探，别堆词。**
- 结果条目结构：`div.search_item`，自定义复选框 `span.checkbox_icon`（有 `checked` class），题名在 `.tit a`，类型标签 `.type_tab`。
- 翻页/每页条数：结果区顶部有 `每页显示 10 / 30 / 50`、`主题排序 / 时间排序`。

**已选**：点 `span.checkbox_icon` 即勾（JS click 有效），顶部「已选文献 N 清除 导出文献」。

**导出（实测打通，关键在 hover 菜单）**：

1. 页面**常驻 `el-loading-mask` 遮罩**，会盖住导出按钮（`elementFromPoint` 命中 `el-loading-spinner`），JS click 一律无效 → 先 `document.querySelectorAll('.el-loading-mask,.el-loading-spinner').forEach(e=>e.remove())`，再走 CDP 真实鼠标。
2. **悬停** `div.exportBtn`（导出文献）→ 浮出格式菜单：**GB/T 7714-2015 / MLA / APA / 复制到剪贴板**。
3. 点 `GB/T 7714-2015` → 引用直接渲染进页面文本，位置在 `body.innerText` 里**紧跟「复制到剪贴板」之后**。
4. 一条命令搞定：`pwsh -File "$S\scholar-export.ps1" -Tab <外文库 tab_id>` → 直接打印引用。

**收尾**：外文库的已选与 kns 分开，同样要清（点顶部「清除」，或直接关掉外文库标签）。

## 交付

按用户要的数量交齐；只要引用时按年份倒序分组、编号连续、逐字用导出原文（仅清空格），不写摘要、推荐语、网址，也不加“仅供学习”之类的话。够数立刻停，不在检索页继续找“更好”的。

**篇目类型优先期刊**：用户（或其导师）通常用「总库/外文库 → 主题或题名 = 关键词」这种最朴素的检索去核对，只能对上**期刊论文**这一类。外文库里 `Book Chapter` / `Book` 记录要一层套一层（书名页 → 章节列表 → 章节页）才找得到，而且知网的 GB/T 文本**会漏掉书名**（如 `IGI Global Scientific Publishing, 2026, :127-146.`，字面搜不到），容易被质疑。所以：**能凑够就用 `Journal` / `外文期刊` 记录，凑不够再考虑图书章节，并在交付时说明怎么定位。**

**交完立刻清空已选**（固定收尾动作，约 10 s）：

```powershell
pwsh -File "$S\cnki-clear-selection.ps1" -Tab <任一结果页 tab_id>
agent-browser-cli close --tab <本轮自己开的结果页 tab_id>   # 逐个关掉
```

理由见「极速模式」第 5 条：积压会挡住老文献，而「清除」按钮无效，下一次任务就得为此再花半小时。

## 边界

每篇都必须有对应知网记录和实际导出文本；只有检索结果、第三方文献表或自行排版不算完成。无结果、导出失败或访问受限就换同主题候选，补不齐时明确列出缺口，不编造引用。导出文本若出现 `111330-.` 之类异常，原样保留并在引用之外简短标注，不静默改正后称原样导出。一个浏览器会话内顺序操作，自己开的检索/导出标签用完 `agent-browser-cli close --tab <id>` 逐张关掉。
