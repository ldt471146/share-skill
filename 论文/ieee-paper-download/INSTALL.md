# ieee-paper-download Skill 安装指南

## 前置依赖

本 skill 依赖 **agent-browser-cli**（本机 Chrome 桥接自动化工具，保留登录态/Cookie）。

### 1. 安装 agent-browser-cli

```bash
npm install -g agent-browser-cli
```

> 若本机已配置 agent-browser-cli（如 `C:\Users\<用户>\.agent-browser-cli\` 存在），跳过此步。

### 2. 确认 Chrome 与桥接扩展

- 安装 Chrome 浏览器
- agent-browser-cli 首次使用会自动通过扩展桥连接 Chrome，无需手动配置

### 3. 安装 ieee-paper-download skill

```bash
# 方式一：从 Git 仓库安装（推荐）
git clone <本仓库地址> ~/.agents/skills/ieee-paper-download

# 方式二：手动复制目录
```

### 4. 验证安装

```bash
# 用一篇已知开放获取论文测试（IEEE JSTARS，CC BY）
pwsh -File ~/.agents/skills/ieee-paper-download/scripts/download-ieee-paper.ps1 -ArticleId 11505776 -OutPath "$env:USERPROFILE\Desktop\test.pdf"
```

看到 `SUCCESS` 即安装成功。

## 常见问题

| 问题 | 处理 |
|------|------|
| 报错 "This paper is NOT open access" | 论文是订阅制，需要机构账号在 Chrome 中登录后重试 |
| 报错 "PDF URL was not captured" | WAF 限流，重新运行（脚本会自动重载页面重试 3 次） |
| 无浏览器标签页 | 脚本会自动启动 Chrome；确保已安装桥接扩展 |
