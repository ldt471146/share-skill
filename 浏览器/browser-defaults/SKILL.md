---
name: browser-defaults
description: >
  本机浏览器任务默认策略（用户已确认的长期偏好）。所有打开网站、浏览页面、截图、抓取页面数据、
  填表、点击、登录站点的任务，默认使用 agent-browser-cli 控制用户真实 Chrome（保留登录态/Cookie），
  不要改用 Playwright MCP、Selenium、agent-browser（Vercel）等其它方案。本 skill 记录本机已验证的
  默认启动方法（快速启动脚本）和命令速查，避免每次踩坑。触发词：默认浏览器、浏览器策略、打开网站、
  浏览器自动化、快速启动。
when-to-use: >
  Always. 任何需要打开网页、看网页内容、截图、操作网页的任务，先按本 skill 的默认启动流程拉起
  agent-browser-cli 管理的 Chrome，再执行操作。仅在用户明确要求不用浏览器时（如只查服务器）
  才改用 curl / plink 等命令行方式。
allowed-tools: Bash(agent-browser-cli:*), Bash(pwsh:*)
---

# 浏览器任务默认策略（本机固化 · v2）

## 核心原则（用户确认的长期偏好）

1. **默认用 `agent-browser-cli`** 操作真实 Chrome（保留登录态/Cookie）。
2. 不要使用 Playwright MCP、Selenium、Vercel `agent-browser`、无头浏览器替代。
3. 只查服务器/接口（不需要渲染页面）时优先 curl / plink，不必开浏览器。

## ⚡ 默认启动方式（快速启动脚本，唯一标准）

**直接用快速启动脚本**（已固化为默认，勿再手动拼命令）：

```powershell
pwsh -File "$env:USERPROFILE\.agent-browser-cli\start-fast.ps1" "https://目标网址"
```

脚本行为：
- Chrome 未运行时：`Start-Process` 带 `--load-extension`（扩展桥）启动并打开 URL，等 12 秒
- Chrome 已在运行：**不杀任何进程**，直接 `agent-browser-cli open` 打开标签
- 最后自动执行 `agent-browser-cli tabs` 确认连接

### 关键红线（血泪教训）
- **绝不要 `Stop-Process -Force` 杀所有 chrome 进程**——会误杀用户正在使用的浏览器窗口！
- `start-chrome-with-bridge.ps1`（旧脚本）不可靠：前台会卡住超时，**不要用**
- 如果 tabs 为空：等 5-10 秒重试 `tabs`，仍失败才 `status` / `doctor` 排障

## 常用命令速查

```bash
agent-browser-cli tabs                          # 列出标签页（拿 tab_id / session_key）
agent-browser-cli scan --text-only              # 看页面正文内容
agent-browser-cli snapshot --limit 200          # 找按钮/链接，生成 @e 引用
agent-browser-cli click '@e1' / click 'button[type=submit]'
agent-browser-cli fill '@e2' '内容'
agent-browser-cli screenshot --out E:\16核16g\页面.png
agent-browser-cli exec --tab <tabId> 'return document.title'
agent-browser-cli send-keys --tab <tabId> --target '<selector>' 'Enter'
```

- 高层命令支持 `--tab <tabId>` / `--profile <label>`；`@e` 只在最近一次 snapshot 内有效
- 慢页面：`click '@e1' --wait-js 'return document.body.innerText.includes("完成")' --wait-timeout 10`
- **真实文本输入**（登录框、搜索框等受控组件）：CDP `Input.insertText` / `Input.dispatchKeyEvent`，合成 JS 事件常被框架忽略
- **真实鼠标点击**（受控 UI）：CDP `Input.dispatchMouseEvent`（mousePressed+mouseReleased，先取元素坐标）

## 注意事项

- 操作的是**用户真实 Chrome**，保留登录态；对用户可见，属正常现象
- 通信走 127.0.0.1（daemon 18767 / 扩展 18765），数据不外发
- 截图/PDF 必须让 CLI 写文件并返回路径，不要把 base64 塞进上下文
- SPA 页面 `scan` 可能读到空数据，用截图或 `exec` 取 `document.body.innerText`
- 任务结束可 `agent-browser-cli close --tab <tabId>` 关闭标签页，或留给用户
- daemon 空闲会退出（TTL 5 分钟）：下次任务直接跑命令，CLI 会自动拉起 daemon
