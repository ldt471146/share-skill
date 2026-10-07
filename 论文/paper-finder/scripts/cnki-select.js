const want = Array.isArray(window.__CNKI_WANT) ? window.__CNKI_WANT : [];
if (!want.length) return 'set window.__CNKI_WANT first, e.g. window.__CNKI_WANT=["题名子串"]';
const rows = [...document.querySelectorAll('table.result-table-list tbody tr')];
const done = [];
const missing = [];
want.forEach(w => {
  const key = String(w).replace(/\s+/g, '');
  const tr = rows.find(r => (r.querySelector('.name')?.innerText || '').replace(/\s+/g, '').indexOf(key) >= 0);
  if (!tr) { missing.push(w); return; }
  const cb = tr.querySelector('input[type=checkbox]');
  if (cb && !cb.checked) cb.click();
  done.push((tr.querySelector('.name')?.innerText || '').trim().slice(0, 40));
});
return JSON.stringify({ done, missing, selected: document.getElementById('selectCount')?.textContent || '' });
