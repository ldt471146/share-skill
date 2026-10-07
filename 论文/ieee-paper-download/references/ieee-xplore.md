# IEEE Xplore 下载参考

## 真实 PDF URL 结构

成功捕获的 PDF 直链形如：

```
https://ieeexplore.ieee.org/ielx8/<ISSUE>/<ISSUE2>/<ARTICLE_ID>.pdf?tp=&arnumber=<ARTICLE_ID>&isnumber=<ISSUE>&ref=<BASE64>
```

- `<ARTICLE_ID>`：文档号（URL `/document/<id>`）
- `<ISSUE>`：期刊卷期号（如 11278119）
- `ref`：base64 编码的 Referer 页面 URL

## 会话 Cookie 关键项

| Cookie | 作用 |
|--------|------|
| `CloudFront-Policy` / `CloudFront-Signature` / `CloudFront-Key-Pair-Id` | CloudFront 签名授权（会话级） |
| `aws-waf-token` | WAF JS 挑战令牌 |
| `TS*` / `TSaf*` | 防爬追踪 |
| `JSESSIONID` / `WLSESSION` | 会话 |

## 已验证失败路径（勿重试）

| 方法 | 结果 |
|------|------|
| 直连 `stamp.jsp` | 6KB 反爬 HTML |
| 直连 `iel8/<issue>/<id>.pdf` | 6KB 反爬 HTML |
| 直连 `mediastore/.../*.pdf` | 403 |
| CDP `Page.setDownloadBehavior` | 浏览器级命令被代理禁止 |
| PDF 查看器内 JS | 原生插件页无 JS API |
| 不带 Cookie 请求 `ielx8` | 403 / 反爬页 |
