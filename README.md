# Share-Skill

个人 AI Agent Skills 合集（按类别组织）。每个 skill 一个目录，目录内是它的 `SKILL.md` 及附带脚本 / 资源。

## 目录结构

```
论文/                    → 找文献、取引用、下全文
  paper-finder/          → 知网检索 + GB/T 7714 引用导出（中/外文库，含速查脚本）
  cnki-search/           → 知网检索、论文详情、参考文献
  ieee-paper-download/   → IEEE Xplore PDF 下载（绕 WAF）

阅读/                    → 读书、读论文、读代码库
  how-to-read-a-book/    → 《如何阅读一本书》方法论读书
  research-reading/      → 科研论文精读与证据比较
  github-project-learning/ → GitHub 教程与项目学习

浏览器/                  → 浏览器自动化
  agent-browser-cli/     → 控制真实 Chrome（登录态/Cookie/CDP/网络）
  browser-defaults/      → 本机浏览器默认策略

工作流-comet/            → Comet 工作流全家桶（13 个）
工作流-openspec/         → OpenSpec change 工作流（11 个）

开发/                    → 计划、执行、评审、测试、收尾（11 个）
技能建设/                → 写 skill、找 skill
界面设计/                → UI/UX 设计库、桌面工具风外壳
终端与工具/              → Pebrel 终端工作区
```

## 类别索引

| 类别 | 数量 | 说明 |
|---|---|---|
| 论文 | 3 | 检索、引用导出、全文下载 |
| 阅读 | 3 | 读书 / 读论文 / 读项目 |
| 浏览器 | 2 | 真实 Chrome 自动化 |
| 工作流-comet | 13 | Comet Classic / Native 全流程 |
| 工作流-openspec | 11 | OpenSpec change 全流程 |
| 开发 | 11 | 计划 → 执行 → 评审 → 验证 → 收尾 |
| 技能建设 | 2 | 编写与发现 skill |
| 界面设计 | 2 | UI/UX 决策库、app shell 风格 |
| 终端与工具 | 1 | 终端工作区控制 |
| **合计** | **48** | |

## 使用

把需要的类别（或单个 skill 目录）复制到你的 skills 目录即可：

```bash
# 只要论文类
git clone --depth 1 https://github.com/ldt471146/share-skill.git
cp -r share-skill/论文/* ~/.agents/skills/
```

Claude Code / Codex / DSH 的 skills 目录通常是 `~/.agents/skills/` 或 `~/.codex/skills/`。

## 维护

`skills.json` 是机器可读索引（类别 → skill 列表），改动后重新生成：

```powershell
pwsh scripts/build-index.ps1
```
