// 读 dm8 导出页的引用全文（配合 cnki-export-scroll.js 先把懒加载的列表滚出来）。
// 用法：agent-browser-cli exec --tab <export_tab> --file .../cnki-export-dump.js
// 可选：先设 window.__CNKI_FILTER = "关键词"，只返回命中的条目。
const el = document.getElementById('result');
if (!el) return JSON.stringify({ error: 'no #result — 不是 dm8 导出页' });
const text = el.value || el.innerText || '';
const blocks = text.split(/\n(?=\[\d+\])/).map(s => s.replace(/\s+/g, ' ').trim()).filter(Boolean);
const kw = window.__CNKI_FILTER;
const kept = kw ? blocks.filter(b => new RegExp(kw).test(b)) : blocks;
return JSON.stringify({ total: blocks.length, kept: kept.length, blocks: kept });
