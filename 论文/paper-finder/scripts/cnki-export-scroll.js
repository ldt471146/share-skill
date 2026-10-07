// 触发 dm8 导出页的懒加载：用定时器做「渐进式滚动」，制造多次 scroll 事件
// （一次 scrollTo 到底有时不触发加载；逐步 scrollBy 更稳）。不等结果就返回，
// 由调用方 sleep 后再看 #result 条数是否增长，必要时重复调用。
// 用法：agent-browser-cli exec --tab <export_tab> --file .../cnki-export-scroll.js
(function () {
  const step = 500;
  let y = window.scrollY;
  let i = 0;
  const timer = setInterval(() => {
    y += step;
    window.scrollTo(0, y);
    i++;
    if (i > 40 || y > (document.body.scrollHeight + 1000)) {
      clearInterval(timer);
      window.scrollTo(0, document.body.scrollHeight);
    }
  }, 120);
})();
return 'scrolling';
