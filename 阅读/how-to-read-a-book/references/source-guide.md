# 规则出处与复核

本技能从用户提供的《如何阅读一本书》中文 EPUB 提取，版本页说明据 1972 年英文版翻译，译序署郝明义并说明与朱衣合作。原书 PDF 由该 EPUB 转换，正文曾逐字核对一致。

规则正文为忠实意译。作者的正式分析阅读十五条对应 A01–A15；F、G、S 和 A16 之后均为本次整理的检索编号，不是作者另列的条数。流程文件是将这些规则组织成对话动作的操作约定。

当前原书规则保留 125 条、482 处短摘；按用户用途删除的范围见 [coverage.md](coverage.md)。科研阅读、GitHub 学习与笔记格式属于应用扩展，分别说明于 [科研方法边界](../../research-reading/references/method-boundaries.md)、[项目学习方法边界](../../github-project-learning/references/method-boundaries.md) 和 [公共笔记约定](note-contract.md)。这些新增程序没有计入原书提炼数量。

## 回到原文

在 [evidence.json](evidence.json) 按规则 ID 查 owner、paragraph_id、quote、epub 和 pdf_page。quote 是连续的原文短摘，完整段落仍需在原书中阅读。paragraph_id 是本次按 EPUB 段落生成的定位，不是原书印刷编号。PDF 页码是本次 424 页文件的第几页，包含封面，不是页脚印刷页码，也不能套用到另一版 PDF。

原文件 SHA-256、各章范围见 [source-metadata.json](source-metadata.json)。原书文件与本机路径不随技能发布；请自行提供同一版本的 EPUB 或对应的 424 页 PDF 复核。源文件仅用于本技能出处复查；使用本技能阅读其他书时应读取那一本的材料。

结构和原文证据可用 [validate_skill.py](../scripts/validate_skill.py) 复核：

```text
python scripts/validate_skill.py --source 原书.epub
python scripts/validate_skill.py --source 原书.pdf
```

脚本使用 Python 与 PyYAML；核对 PDF 时另外使用 PyMuPDF。须用 --source 指定原书；只查结构时使用 --structure-only，结果不表示已复核原文。源码或版本不同会报告哈希差异，不会把另一版的页码当成已验证。

它检查三个入口预算、同级依赖、路由、链接、跨模块调用环、唯一规则位置、来源文件身份和短摘匹配；不能证明意译的语义等价或任何未来阅读行为。完整段落的语义核对和实际场景结果见 [validation.md](validation.md)。

逐章范围与未提取原因见 [coverage.md](coverage.md)；去重关系见 [consolidation.json](consolidation.json)。更改规则时回到原段落及上下文，保留适用条件和例外；新增作者未说的方法须标成补充，不放进本书规则。
