# ieee-paper-download

Claude Code / Codex / DSH skill，用于从 **IEEE Xplore** 下载论文 PDF（开放获取 / CC BY / 机构授权论文）。

## 功能

- **一键下载**：`download-ieee-paper.ps1` 自动完成全部流程，只需提供论文 Article ID
- **绕过 WAF**：IEEE 有 aws-waf-token JS 挑战 + CloudFront 签名 Cookie 双重反爬，脚本通过真实浏览器会话 + 网络监听捕获真实 PDF 直链后重放下载
- **自动重试**：WAF 短时限流（`?denied=`）时自动重载页面重试 3 次
- **订阅墙识别**：遇到订阅制论文（非开放获取）时明确提示，不白忙活
- **输出校验**：下载后校验 `%PDF` 文件头，防止拿到反爬 HTML

## 依赖

- [agent-browser-cli](https://github.com/)（本机 Chrome 桥接自动化，保留登录态/Cookie）
- Chrome 浏览器
- PowerShell 7+（pwsh）
- 目标论文需为**开放获取（CC BY/OA）或机构已授权**

## 安装

```bash
# 方式一：从 Git 仓库安装（推荐）
git clone <本仓库地址> ~/.agents/skills/ieee-paper-download

# 方式二：手动复制
# 将 ieee-paper-download 目录放入你的 skills 目录（如 ~/.agents/skills/ 或 ~/.claude/skills/）
```

## 使用

```bash
# 一键下载到桌面（默认文件名 paper_<id>.pdf）
pwsh -File ieee-paper-download/scripts/download-ieee-paper.ps1 -ArticleId 11505776

# 指定输出路径
pwsh -File ieee-paper-download/scripts/download-ieee-paper.ps1 -ArticleId 11505776 -OutPath "$env:USERPROFILE\Desktop\paper.pdf"

# 用完整文档 URL
pwsh -File ieee-paper-download/scripts/download-ieee-paper.ps1 -DocumentUrl "https://ieeexplore.ieee.org/document/11505776"
```

Article ID 是文档 URL 里 `/document/` 后面的数字：`https://ieeexplore.ieee.org/document/11505776` → `11505776`。

## 工作原理（为什么这样能过 WAF）

IEEE 的 PDF 由 CloudFront 分发，真实文件在 `ielx8` 路径下，靠 `CloudFront-Policy` / `CloudFront-Signature` / `CloudFront-Key-Pair-Id` 三个**会话级签名 Cookie** 授权，外加 `aws-waf-token` JS 挑战。PowerShell 无法自行生成这些 Cookie，因此必须：

1. 用真实 Chrome 打开文档页（让 WAF 挑战通过、生成签名 Cookie）
2. `network start` 监听 → 点击 Download PDF
3. 从网络日志捕获 `ielx8` 真实 PDF 直链
4. 导出浏览器 Cookie + 完整 Sec-Fetch 请求头重放下载

详见 `SKILL.md` 的踩坑清单（所有已验证失败的路径）。

## 边界

- 仅支持**开放获取 / 机构授权**论文；订阅制论文会明确报错
- 若学校有 IEEE 机构订阅，先在 Chrome 中通过机构账号登录一次即可下载订阅制论文
- 本 skill 不提供、也不支持绕过付费墙抓取订阅制论文
