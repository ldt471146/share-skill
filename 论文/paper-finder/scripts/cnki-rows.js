const cell = (tr, sel) => (tr.querySelector(sel)?.innerText || '').replace(/\s+/g, ' ').trim();
const rows = [...document.querySelectorAll('table.result-table-list tbody tr')].map(tr => ({
  title: cell(tr, '.name'),
  author: cell(tr, '.author'),
  source: cell(tr, '.source'),
  date: cell(tr, '.date'),
  type: cell(tr, '.data')
}));
return JSON.stringify({
  page: (document.getElementById('countPageDiv')?.innerText || '').replace(/\s+/g, ' ').trim(),
  selected: document.getElementById('selectCount')?.textContent || '',
  rows
});
