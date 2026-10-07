# 论文

找文献、取引用、下全文。

| Skill | 用途 |
|---|---|
| **paper-finder** | 知网检索 + GB/T 7714 引用导出。中英文库都支持，附速查脚本（并行探针、批量勾选、一键导出、清空已选）。 |
| **ieee-paper-download** | 从 IEEE Xplore 下载开放获取 / 机构授权论文 PDF（浏览器抓真实 URL + 带 Cookie 重放，绕过 WAF）。 |

## paper-finder 速用

```powershell
# 1) 并行开探针（中文词组 + 单个英文词，别中英混排）
$u = "https://kns.cnki.net/kns8s/defaultresult/index?korder=TI&kw=<URL编码>"

# 2) 勾选目标（跨标签累计，已选要 ≤20）
agent-browser-cli exec --tab <tab> 'window.__CNKI_WANT=["题名子串A"]; "ok"'
agent-browser-cli exec --tab <tab> --file scripts/cnki-select.js

# 3) 导出引用（直开 dm8）→ 读 → 清洗
pwsh -File scripts/cnki-export-all.ps1 -Tab <export_tab> -Filter "关键词"

# 4) 外文库（英文）导出
pwsh -File scripts/scholar-export.ps1 -Tab <外文库 tab_id>

# 5) 收尾：清空已选 + 关标签（必须做，否则下轮被积压卡死）
pwsh -File scripts/cnki-clear-selection.ps1 -Tab <任一结果页>
```

实测：中文 10 篇约 51～66 秒，外文 5 篇约 35～60 秒。

细节与踩坑记录见 `paper-finder/SKILL.md` 与 `paper-finder/RUNS.md`。
