# 阅读套件的安装与维护

套件包含三个同级目录：`how-to-read-a-book`、`research-reading`、`github-project-learning`。本目录是统一入口和共享阅读规则的唯一维护位置；两个专用技能可以直接触发，共用本目录的原书依据与笔记约定。只更新其中一个目录可能造成路径或规则版本不匹配，应从同一 Git 提交安装全部三个目录。

## 安装

仓库：[ldt471146/Share-Skill](https://github.com/ldt471146/Share-Skill)。在已提供 skill-installer 的 Codex 中，可使用其脚本一次安装三个目录：

```text
python <skill-installer目录>/scripts/install-skill-from-github.py --repo ldt471146/Share-Skill --ref main --path how-to-read-a-book research-reading github-project-learning
```

`--ref` 可换成已确认的提交 SHA，以固定版本。脚本默认使用 Codex 的 skills 目录，也可用 `--dest` 指定。已有同名目录时，先把旧目录移到 skills 目录之外作备份，再安装；安装完成前保留备份。也可从同一仓库检出版本，完整复制这三个目录到技能根目录，保持名字不变。更新时替换整个目录，使旧版已移除的文件不会残留。

当前会话正在更新这些技能时，安装与核对完成后从下一轮使用新版本。

## 结构与证据核验

结构脚本需要 Python 与 PyYAML；核对 PDF 时还需 PyMuPDF。以下命令在本目录运行：

```text
python scripts/validate_skill.py --structure-only
python scripts/validate_skill.py --source /path/to/如何阅读一本书.pdf
```

第一条检查三个入口、同级依赖、路由、规则唯一位置和链接，不表示核验了原文。第二条要求与 [来源记录](references/source-metadata.json) 哈希一致的 EPUB 或 424 页 PDF，并检查短摘匹配；其他版本的页码不能直接套用。原书与完整提取文本不在仓库中。含义是否忠实仍需人工对照原文，验证范围见 [验证记录](references/validation.md)。

## 维护边界

- 改原书提炼：只改本目录 `rules/` 的相应规则，同时核对 `references/evidence.json`、上下文和来源定位。
- 改科研程序：改 `research-reading`；实验设计核对、可比性和复现状态属于应用扩展。
- 改 GitHub 教学：改 `github-project-learning`；版本、代码路径、示例执行和教学安排属于应用扩展。
- 改笔记共同行为：改 [note-contract.md](references/note-contract.md)；领域特有字段仍留在领域流程。

入口选路后进入具体流程，子技能读取共享文件，不重新进入总入口。论文与实现的混合任务由科研技能主导，实现步骤返回证据后结束。无需按每种书类、编程语言或笔记动作再注册一个技能；出现独立资料、稳定流程和不同验证条件时再考虑拆分。

本版按用户用途移除社会科学、新闻和文摘的专用规则，保留历史、传记及其他按需书类；生成摘要与读书笔记仍可使用。旧版与原始提炼审查由 Git 历史保存，当前取舍见 [coverage.md](references/coverage.md)。
