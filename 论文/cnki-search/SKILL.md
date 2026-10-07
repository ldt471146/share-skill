---
name: cnki-search
description: >
  在中国知网（CNKI）检索中文学术论文、期刊、学位论文、会议论文，获取论文详情、参考文献，
  并直接输出完整 GB/T 7714 引用（含卷、期、页码、DOI）。触发场景：用户要求搜索知网论文、
  查找文献、检索期刊/学位论文/会议论文、整理参考文献引用，或提到"知网"、"CNKI"、
  "中国知网"、"文献检索"、"论文搜索"等关键词时使用此 skill。
  支持关键词/主题/作者检索、论文详情获取、参考文献提取、批量引用导出。
metadata:
  author: xiaol
  version: "2.1.0"
---
# CNKI 知网检索 Skill

## 概述

通过独立的 `cnki` Go CLI 访问中国知网，执行学术文献检索与引用导出任务。
**搜索走 HTTP 接口，详情页走真实浏览器**（`/kcms2/` 页面有反爬，裸 HTTP 必被拦截）。

Claude 在这里的职责是：

1. 把用户的自然语言需求翻译成 `cnki` 命令行参数
2. 执行命令，解析返回的 JSON
3. 按用户要求渲染成表格 / 引用格式 / 详细卡片

## 前置依赖

### 工具链检查

执行任何操作前，先确认 `cnki` 命令可用：

```bash
cnki --version
```

本机已安装并在 PATH 中。若换机器且未安装，按 `INSTALL.md` 安装（注意该文件是 v1 残留，与本文冲突处以本文为准）。

### 关键前提：浏览器 profile 必须已解过验证

**`cnki detail` / `cnki batch` 必须走 `--browser`，且必须复用已通过知网验证码的 Chrome profile。**

- 裸 HTTP 请求 `/kcms2/` 详情页 → 必被反爬拦截（退出码 2）。
- 全新 profile 首次访问 → 会撞上「请依次点击【特,主,也】」点选式验证码。
- 复用已解过验证的 profile → 畅通。本机默认 profile 为
  `%LOCALAPPDATA%\cnki-search\chrome`（`cnki` 会自动优先使用它）。

若某台机器上没有这个 warmed profile，**先跑一次有头模式手动过一次验证码**：

```bash
cnki detail "<任一详情页 url>" --browser --profile-dir "%LOCALAPPDATA%\cnki-search\chrome"
```

过完之后该 profile 长期复用，后续 `--headless` 即可批量跑。

### 登录态检查

导出引用、部分详情页需要登录。首次在该 profile 上访问知网时登录一次即可，之后 cookie 长期复用。

若命令返回退出码 `2`（ErrCaptcha），说明验证码或登录失效，按上文重新过一次；不要在同一秒内反复重试。

## 检索流程

### Phase 1：明确检索需求

与用户确认以下信息（缺省时使用默认值）：

| 参数 | CLI flag | 可选值 | 默认 |
|------|---------|--------|------|
| 关键词 | `<query>` 位置参数 | 检索词，多词用空格 | 必填 |
| 检索字段 | `--field` | topic / keyword / title / author / abstract / fulltext / doi | topic |
| 起始年份 | `--from` | YYYY | 不限 |
| 截止年份 | `--to` | YYYY | 不限 |
| 文献类型 | `--type` | journal / master / phd / conference / newspaper / yearbook（可重复） | 全部 |
| 来源类型 | `--source` | sci / ei / core / cssci / cscd（可重复） | 全部 |
| 排序方式 | `--sort` | relevance / date / cited / downloads | relevance |
| 结果数量 | `--size` | 任意正整数（≤500） | 20 |

缺少关键词时必须向用户追问，其余可用默认值。

## 模糊检索（默认策略 · 必须遵守）

用户给出一个主题词时，**默认按「模糊检索」理解**：他要的是「相关的一批论文」，不是题名精确匹配。

因此：

- **不要**只用他给的那一个词搜一次就交付
- **不要**用 `--field=title` 做精确题名匹配（长题名在这个 CLI 上频繁假空，且会把结果收窄到几乎没有）
- **要**主动扩词、合并、过滤、排序，再取前 N 篇

### 标准流程

1. **多词扩检**：把主题拆成 3~6 个同义/上下位检索词，逐个跑 `--field=topic`，合并结果。
2. **合并去重**：按题名归一化去重（**先去空格**——CNKI 会在题名里插入 `<em>` 高亮残留空格）。
3. **主题过滤**：题名须含主题词或其近义词。
4. **类型过滤**：用户要「期刊引用」时，剔除 source 为 `XX大学`/`XX学院`（学位论文）和 `XX报`（报纸）的记录。
5. **排序**：技术实现类优先（题名含 `系统|平台|小程序|设计|实现|开发|Spring|Vue|Java|Web`），再按被引降序。
6. **取前 N 篇**，写 URL 列表，用 `cnki batch` 批量出引用。

### 一键脚本（推荐，别手写流程）

`scripts/fuzzy-search.ps1` 已实现上述全部步骤：

```powershell
$sk = "$env:USERPROFILE\.agents\skills\cnki-search\scripts\fuzzy-search.ps1"

# 1) 模糊检索 -> 产出 URL 列表
& $sk -Topic '文旅|旅游|景区|非遗' `
      -Query '旅游 系统 设计与实现','文旅 平台','智慧旅游 系统','旅游 推荐系统' `
      -From 2023 -To 2026 -TopN 10 -DelaySec 12 `
      -OutUrls "$env:TEMP\urls.txt" -OutJson "$env:TEMP\pool.json"

# 2) 批量出引用
cnki batch --from-file "$env:TEMP\urls.txt" --headless --format=citation --delay 12s
```

要点：

- `-Query` 是**数组**，多个词用**逗号**分隔（`-Query 'a','b'`），不能重复写 `-Query`。
- `-Topic` 是过滤用的正则；`-TopN` 是最终篇数。
- 默认剔除学位论文和报纸；需要时加 `-IncludeTheses` / `-IncludeNewspapers`。
- 脚本内已含限速与去空格去重，**不要**再手工重跑一遍检索。
- 注意：脚本里那个参数叫 `-TopN` 而不是 `-Top`，因为 PowerShell 变量名大小写不敏感，
  `[int]$Top` 与局部变量 `$top` 是同一个变量，给 `[int]` 约束的变量赋数组会直接报错。

### 扩词示例

| 用户说 | 应扩检的词 |
|---|---|
| 文旅 / Spring文旅 | 旅游 系统 设计与实现、文旅 平台、智慧旅游 系统、旅游 推荐系统、文化旅游 数字化 平台 |
| 二手汽车 / 二手车 | 二手车、二手车交易、二手车交易平台、二手汽车市场、二手车电商 |
| XX管理系统 | XX 系统 设计与实现、XX 平台、基于SpringBoot的XX、XX小程序 |

**为什么要多词**：单词命中动辄上万条（「文旅」= 25287 条），相关度排序会把行业新闻、教学改革类顶到前面，
真正的系统实现类论文被淹没。多词扩检 + 过滤才能把它们捞出来。

### 节奏（防验证码）

- 多词扩检**串行**，每次间隔 ≥10s
- 撞到 `exit=3`（假空）或 `exit=2`（验证码）→ 等 30~60s 再试，**不要连续重试**
- 批量抓引用用 `--delay 12s`
- 真瓶颈是**请求频率**，不是 IP；换 IP 解决不了刷太快的问题

### Phase 2：执行检索

组装命令，默认 JSON 输出方便后续解析：

```bash
cnki search "深度学习 图像识别" \
  --field=topic \
  --from=2020 \
  --source=core \
  --sort=cited \
  --size=30 \
  --format=json
```

Bash 示例（把 JSON 存到变量中）：

```bash
RESULT=$(cnki search "大语言模型" --size=20 --sort=cited --format=json)
# 用 jq 拿到前 5 条标题
echo "$RESULT" | jq -r '.results[:5] | .[] | .title'
```

#### JSON 输出结构

```json
{
  "query": {"q":"深度学习","field":"topic","sort":"cited","size":20},
  "total_hits": 12345,
  "fetched": 20,
  "results": [
    {
      "seq": 1,
      "title": "...",
      "url": "https://kns.cnki.net/kcms2/article/abstract?v=...",
      "authors": ["张三","李四"],
      "source": "计算机学报",
      "year": 2024,
      "issue": "2024-03",
      "cited": 45,
      "downloads": 230
    }
  ]
}
```

### Phase 3：获取论文详情（可选）

当用户需要某篇论文的完整信息时，**必须使用上一步返回的 `url`**（它带会话参数，不能手工拼接）：

```bash
cnki detail "<paper url from step 2>" --browser --headless --format=json
```

`--browser` 是必需项：详情页有反爬，裸 HTTP 会被拦。

加 `--with-refs` 可同时抽取参考文献：

```bash
cnki detail "<paper url>" --browser --with-refs --format=json
```

返回字段：`title / authors / institutions / abstract / keywords / doi / clc / source / issue / year / volume / issue_no / pages / source_kind / fund / cited / downloads / references`。

### Phase 4：批量抓取引用（推荐，一次跑完 N 篇）

**需要多篇引用时不要逐篇调用 `detail`**——每篇都要重启浏览器，慢且更容易触发风控。
用 `batch`：单个浏览器会话按顺序跑完所有 URL。

```bash
# 1) 先把 urls.txt 写好（每行一个从 search 拿到的详情页 url）
# 2) 一次性抓完并输出引用
cnki batch --from-file urls.txt --format=citation --out refs.txt --delay 3s
```

| flag | 说明 | 默认 |
|------|------|------|
| `--from-file` | 从文件读 URL（每行一个，`#` 开头为注释） | — |
| `--format` | `citation` / `json` / `markdown` | `citation` |
| `--delay` | 每篇间隔，防触发风控 | `3s` |
| `--out` | 同时写入文件 | — |
| `--max-failures` | 连续失败达到该数即停（0 = 不停） | `3` |
| `--headless` | 无头运行 | 有头 |

位置参数也可直接给 URL：`cnki batch <url1> <url2> ...`

`--format=citation` 输出**完整 GB/T 7714**：

```
[1] 慕银平, 徐彦. 垂直二手交易平台商业模式价值逻辑研究——基于扎根理论的探索性案例分析[J]. 工业工程与管理, 2024, 29(5): 202-214. DOI: 10.19495/j.cnki.1007-5429.2024.05.020.
```

卷、期、页码、DOI 均从详情页抽取，非拼接。若某篇详情页本身没有卷期页码（如短讯、无卷期栏目），
则该条不含这一节——**这是知网数据缺失，不要自行补造**。

### Phase 4b：单独获取参考文献（可选）

```bash
cnki refs "<paper url>" --format=json
```

返回 `[{seq, text}, ...]` 数组。

### Phase 5：格式化输出

根据用户需求选择 CLI 自带的输出格式，或把 JSON 重新渲染：

#### 人类可读表格

CLI 直出，无需二次处理：

```bash
cnki search "深度学习" --size=10 --format=table
```

#### GB/T 7714 引用格式

```bash
cnki search "深度学习" --size=10 --format=citation
```

输出：

```
[1] 张三, 李四. 基于深度学习的图像识别研究[J]. 计算机学报, 2024.
[2] 王五. 卷积神经网络综述[J]. 软件学报, 2023.
```

#### Markdown 详细卡片

```bash
cnki detail "<paper url>" --with-refs --format=markdown
```

输出（对话中可直接展示）：

```markdown
### 《论文标题》

- **作者**：张三, 李四
- **单位**：XX大学XX学院
- **来源**：《期刊名》2024年第3期
- **DOI**：10.xxxx/xxxx
- **被引**：15 次 | **下载**：230 次
- **关键词**：关键词1; 关键词2

**摘要**：……
```

#### 在对话中直接呈现

默认把 JSON 里的 `results` 渲染成如下 Markdown 表格给用户看：

```
## 知网检索结果：「{关键词}」

命中 XX 条，以下为前 N 条（按{排序方式}排序）：

| # | 标题 | 作者 | 来源 | 年份 | 被引 |
|---|------|------|------|------|------|
| 1 | ... | ... | ... | 2024 | 15 |
```

## 错误处理

`cnki` 退出码约定：

| 退出码 | 含义 | 应对 |
|--------|------|------|
| 0 | 成功 | 解析 JSON 继续 |
| 1 | 一般错误（网络/DOM 异常） | 读 stderr 提示用户 |
| 2 | 验证码或反爬拦截 | 提示用户运行 `cnki login`，或改用 `--headed` 重试 |
| 3 | 检索结果为空 | 建议用户调整关键词、放宽时间、换检索字段 |
| 4 | 参数非法 | 读 stderr 的校验提示，重新询问用户 |

### 遇到退出码 2（验证码）

优先级从高到低：

1. 引导用户跑 `cnki login` 更新登录态，然后重试
2. 若用户不想登录，改用 `--headed` 人工过一次验证码：
   ```bash
   cnki search "..." --headed --size=10
   ```
3. 告知用户短期频繁检索容易触发风控，建议降低频率

### 遇到退出码 3（无结果）

- 放宽 `--from/--to` 年份
- 把 `--field` 从 `title` 改为 `topic` 或 `keyword`
- 去掉 `--source` / `--type` 的限制
- 建议同义词替换（"大语言模型" → "LLM" / "预训练语言模型"）

## 操作节奏

- **串行调用**：避免在同一秒发多个 `cnki search`；必要时用户可以连续追问但别并行触发
- **先 search 后 detail**：detail URL 必须来自 search 返回的 `url` 字段，不要凭空构造
- **批量详情要节制**：如果用户要 20 篇的完整详情，分批执行或直接用 search 自带的信息 + 摘要抽取

## 与其他 Skill 协作

### 与 lunwen skill 协作

当 lunwen（毕业论文写作）skill 需要文献检索时，本 skill 可被调用来：

1. 根据论文主题检索相关文献：`cnki search "主题" --source=core --sort=cited`
2. 提取参考文献元数据：`cnki detail <url>`
3. 输出 GB/T 7714 格式：`cnki search ... --format=citation`
4. 筛选高被引/核心期刊文献

### 与 research-writing-skill 协作

1. 按主题批量检索：`cnki search "..." --size=30 --format=json`
2. 提取摘要和关键词：迭代 `cnki detail <url>` for top N
3. 为文献综述提供素材

## 子 Agent 使用指南

在子 Agent prompt 中调用本 skill：

```
必须加载 cnki-search skill 并遵循指引。
任务：用 `cnki` 命令行在知网上获取关于「{主题}」的学术文献，需要 {N} 篇，
按被引频次排序，仅限核心期刊，时间范围 2020-2025。
将结果以 GB/T 7714 格式返回。
```

## 任务结束

完成检索后：

1. 向用户呈现格式化结果（默认 Markdown 表格）
2. 如果用户要了引用格式，附上 `--format=citation` 的输出
3. 询问是否需要查看某篇的详情（`cnki detail <url>`）
4. 询问是否需要调整检索条件重新搜索

## 参考：知网站点特性

参见同目录下的 `references/cnki.net.md` —— 记录了 CNKI 的 Vue SPA 架构、反爬行为、已知选择器陷阱等知识。该文件也是 `cnki` 二进制的 DOM 选择器（位于项目 `internal/cnki/selectors.go`）的维护参考。
