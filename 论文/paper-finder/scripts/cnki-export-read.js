const el = document.getElementById('result');
if (!el) return JSON.stringify({ error: 'no #result — this tab is not the dm8 export page' });
const txt = (typeof el.value === 'string' && el.value) ? el.value : (el.innerText || '');
const blocks = txt.split(/\n(?=\[\d+\])/).map(s => s.replace(/\s+/g, ' ').trim()).filter(Boolean);
const kw = window.__CNKI_FILTER;
const kept = kw ? blocks.filter(b => new RegExp(kw).test(b)) : blocks;
return JSON.stringify({ total: blocks.length, kept: kept.length, blocks: kept });
