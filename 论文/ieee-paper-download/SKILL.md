---
name: ieee-paper-download
description: >
  从 IEEE Xplore 下载论文 PDF（开放获取 / CC BY / 机构授权论文）的专用流程与一键脚本。
  IEEE Xplore 有 WAF 反爬（aws-waf-token JS 挑战 + CloudFront 签名 Cookie + APM 脚本），
  直接 Invoke-WebRequest / curl / Python requests 请求 PDF 会被拦截，返回约 6KB 的
  反爬 HTML（含 APM_DO_NOT_TOUCH 脚本）或 403。
  本 skill 是唯一验证可行的下载路径：浏览器加载文档页 → 网络监听捕获真实 ielx8 PDF URL →
  导出浏览器会话 Cookie → PowerShell 带完整 Cookie + Sec-Fetch 请求头重放下载。
  触发词：下载论文、下载 PDF、IEEE Xplore 下载、抓论文、下载这篇论文、paper download。
metadata:
  author: ldt471146
  version: "1.1.0"
---

<skill_resources>
Base directory for this skill: C:\Users\Administrator\.agents\skills\ieee-paper-download
配套脚本：scripts/download-ieee-paper.ps1（一键下载，最推荐直接用）
</skill_resources>

<skill_instructions>
# IEEE Xplore 论文 PDF 下载

## 核心结论（一句话）

**不能用脚本直接请求 PDF URL——必被 WAF 拦截。必须借用真实 Chrome 的会话（Cookie + WAF token），从浏览器网络监听里抓到真实 PDF 直链，再用完整 Cookie 重放下载。**

## 推荐做法（零试错，一条命令）

最优先用配套一键脚本（无需手动开浏览器监听）：

```powershell
pwsh -File "$env:USERPROFILE\.agents\skills\ieee-paper-download\scripts\download-ieee-paper.ps1" `
  -ArticleId 11505776 `
  -OutPath "$env:USERPROFILE\Desktop\paper.pdf"
```

脚本自动完成：开浏览器 → 打开文档页 → 网络监听 → 点击 Download PDF → 捕获 ielx8 直链 → 导出 Cookie → 下载 → 校验 %PDF。参数说明：

- `-ArticleId`：IEEE 论文号（文档 URL 里 `/document/<数字>` 的 `<数字>`）— 必填
- `-DocumentUrl`：完整文档 URL（与 ArticleId 二选一，给了优先用）
- `-OutPath`：保存路径（默认桌面 `paper.pdf`）
- `-NoOpen`：不新开浏览器标签（脚本会在最旧的可用标签上执行，适合浏览器已开着的情况）

## 手动流程（脚本不可用时按此执行）

### 第 1 步：确认论文并拿到 Article ID

论文页 URL 形如 `https://ieeexplore.ieee.org/document/11505776`，最后一段数字就是 Article ID。
搜索页找到论文后点进去即是文档页。

### 第 2 步：浏览器打开文档页 + 启动网络监听

```powershell
# 打开文档页（用 agent-browser-cli，会保留登录态）
agent-browser-cli open "https://ieeexplore.ieee.org/document/<ARTICLE_ID>"
# 等页面加载完（3-5 秒），记录返回的 opened_tab_id
agent-browser-cli network start --tab <TAB_ID>
```

注意：网络监听必须在**点击下载之前**、且**在同一个 tab** 上启动，否则抓不到 PDF 请求。

### 第 3 步：点击 Download PDF 触发真实请求

```powershell
agent-browser-cli exec --tab <TAB_ID> 'const a = document.querySelector("a.stats-document-lh-action-downloadPdf_2"); if (a) { a.click(); return "clicked"; } return "not-found";'
```

等待 5-8 秒让 PDF 请求完成（不要急着查）。

### 第 4 步：从网络监听里捞出真实 PDF 直链

```powershell
agent-browser-cli network list --tab <TAB_ID>
```

在结果里找 `"mimeType": "application/pdf"` 的请求，它的 URL 就是真实直链，形如：

```
https://ieeexplore.ieee.org/ielx8/<ISSUE>/<ISSUE2>/<ARTICLE_ID>.pdf?tp=&arnumber=<ARTICLE_ID>&isnumber=<ISSUE>&ref=<BASE64>
```

**必须用这个 ielx8 直链**（不是 stamp.jsp，不是 mediastore，不是 iel8）。

### 第 5 步：导出 Cookie + 带完整请求头下载

```powershell
# 导出浏览器里 ieeexplore.ieee.org 的全部 Cookie（含 CloudFront 签名 + aws-waf-token）
$cookies = agent-browser-cli exec '{"cmd":"cookies","url":"https://ieeexplore.ieee.org/"}' | ConvertFrom-Json
$cookieStr = ($cookies.result.js_return | ForEach-Object { "$($_.name)=$($_.value)" }) -join '; '

$headers = @{
  'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
  'Referer'    = "https://ieeexplore.ieee.org/document/<ARTICLE_ID>"
  'Cookie'     = $cookieStr
  'Accept'     = 'application/pdf,*/*'
  'Sec-Fetch-Dest' = 'document'
  'Sec-Fetch-Mode' = 'navigate'
  'Sec-Fetch-Site' = 'same-origin'
  'Sec-Fetch-User' = '?1'
  'Upgrade-Insecure-Requests' = '1'
}
Invoke-WebRequest -Uri $pdfUrl -Headers $headers -OutFile "$env:USERPROFILE\Desktop\paper.pdf" -TimeoutSec 180
```

### 第 6 步：校验（必做）

```powershell
$b = [System.IO.File]::ReadAllBytes("$env:USERPROFILE\Desktop\paper.pdf")
# 前 4 字节必须是 %PDF，且大小 > 100KB
[System.Text.Encoding]::ASCII.GetString($b[0..3])
```

返回 `%PDF` 即成功。若只有几 KB 且开头是 HTML/`<APM_DO_NOT_TOUCH>`，说明被 WAF 拦了：换回一键脚本重跑，或重新 open 文档页让浏览器先过 JS 挑战再试。

## 踩坑清单（这些路径都验证过会失败，不要再试）

| 方法 | 结果 |
|------|------|
| `Invoke-WebRequest` 直接请求 `stamp.jsp?tp=&arnumber=...` | ❌ 返回 6KB 反爬 HTML（即使带 Cookie） |
| 直接请求 `iel8/<...>/<id>.pdf`（Google Scholar 缓存链接） | ❌ 6KB 反爬 HTML |
| 直接请求 `mediastore/IEEE/content/media/.../*.pdf` | ❌ 403 Forbidden（需额外签名条件） |
| `Page.setDownloadBehavior` / `Browser.setDownloadBehavior` CDP | ❌ 代理报 "Cannot access browser-level commands"，浏览器级命令被禁 |
| 在 Chrome 内置 PDF 查看器页执行 `PDFViewerApplication` JS | ❌ 查看器是原生插件页，无 JS API；snapshot 也是空树 |
| 浏览器直接新标签打开 `stamp.jsp` | ⚠️ 可打开（标题变 "IEEE Xplore Full-Text PDF:"）但拿到的是 viewer 展示，无法落盘；且多次尝试后会被重定向回 `document/<id>?denied=` |
| 单独请求 `ielx8` 直链但不带 Cookie | ❌ 403 / 反爬页 |
| 带 Cookie 但缺 `Sec-Fetch-*` 头 | ❌ 可能仍被拦（幂等起见全套头都带上） |

## 原理速记（为什么这样能过）

- IEEE 的 PDF 由 CloudFront 分发，真实文件在 `ielx8` 路径下，靠 `CloudFront-Policy` / `CloudFront-Signature` / `CloudFront-Key-Pair-Id` 三个签名 Cookie 授权——这三个 Cookie 是**会话级**的，只有真实浏览器访问过文档页后才有。
- 页面还要求 `aws-waf-token`（JS 挑战生成）和 `TS*` 防爬 Cookie，PowerShell 无法自行生成，必须从浏览器导出。
- 因此**先让浏览器触发一次真实 PDF 请求（点击 Download PDF）**，同时监听网络拿到直链，再带着全套 Cookie 重放，是绕过 WAF 的唯一可靠路径。

## 通用化提示（同类站可借鉴）

其他有反爬的学术站（如 Elsevier/ScienceDirect、Springer）也可套用同一套路：
1. 浏览器打开文章页（带机构登录态）
2. `network start` 监听 → 点击下载按钮
3. 从 network list 里找 `application/pdf` 的真实直链
4. 导出该域 Cookie + 完整浏览器请求头重放下载

## 收尾

下载完成后关闭监听的标签页：

```powershell
agent-browser-cli close --tab <TAB_ID>
```
</skill_instructions>
