param(
    [Parameter(Mandatory = $true)]
    [string]$Tab,

    [int]$WaitSeconds = 5,

    [int]$MaxChars = 3000
)

$ErrorActionPreference = 'Stop'

# 外文库（scholar.cnki.net）导出引用：
#   悬停 div.exportBtn（「导出文献」）→ 浮出格式菜单「GB/T 7714-2015 / MLA / APA / 复制到剪贴板」
#   → 点 GB/T 7714-2015 → 引用直接渲染进页面（在 body 文本里，紧跟「复制到剪贴板」之后）。
# 注意：该页常驻 el-loading-mask 遮罩，JS click 无效，必须用 CDP 真实鼠标事件；
#       多词题名检索普遍「无数据」，单组词（如 library management system）才有结果。

function Invoke-Js([string]$Script) {
    $raw = & agent-browser-cli exec --tab $Tab $Script | Out-String
    if ($LASTEXITCODE -ne 0) { throw "exec failed: $raw" }
    $obj = $raw | ConvertFrom-Json
    if (-not $obj.ok) { throw "exec not ok: $raw" }
    return $obj.result.js_return
}

function Move-Mouse([int]$X, [int]$Y) {
    $p = '{"cmd":"cdp","tabId":' + $Tab + ',"method":"Input.dispatchMouseEvent","params":{"type":"mouseMoved","x":' + $X + ',"y":' + $Y + ',"button":"none"}}'
    & agent-browser-cli exec $p | Out-Null
}

function Click-At([int]$X, [int]$Y) {
    foreach ($t in @('mouseMoved', 'mousePressed', 'mouseReleased')) {
        $btn = if ($t -eq 'mouseMoved') { 'none' } else { 'left' }
        $p = '{"cmd":"cdp","tabId":' + $Tab + ',"method":"Input.dispatchMouseEvent","params":{"type":"' + $t + '","x":' + $X + ',"y":' + $Y + ',"button":"' + $btn + '","clickCount":1}}'
        & agent-browser-cli exec $p | Out-Null
    }
}

$rect = Invoke-Js 'const d=document.querySelector(".exportBtn"); if(!d) return "none"; const r=d.getBoundingClientRect(); return JSON.stringify({x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)});'
if ($rect -eq 'none') { throw '页面上没有 .exportBtn（导出文献），确认在外文库结果页' }
$b = $rect | ConvertFrom-Json

Move-Mouse $b.x $b.y
Start-Sleep -Milliseconds 900

$opt = $null
for ($i = 1; $i -le 5; $i++) {
    $g = Invoke-Js 'const els=[...document.querySelectorAll("*")].filter(e=>(e.textContent||"").trim()==="GB/T 7714-2015" && e.children.length===0); if(!els.length) return "nf"; const r=els[0].getBoundingClientRect(); return JSON.stringify({x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)});'
    if ($g -ne 'nf') { $opt = $g | ConvertFrom-Json; break }
    Move-Mouse $b.x $b.y
    Start-Sleep -Milliseconds 600
}
if (-not $opt) { throw '点不到 GB/T 7714-2015 菜单项（悬停菜单没出现）' }

Click-At $opt.x $opt.y
Start-Sleep -Seconds $WaitSeconds

$text = Invoke-Js ('const t=document.body.innerText.replace(/\r/g,""); const i=t.indexOf("复制到剪贴板"); return i>=0? t.slice(i+6, i+' + ($MaxChars + 6) + ') : "NO-PANEL";')
if ($text -eq 'NO-PANEL') { throw '导出面板没出现，重跑一次（页面前端偶发不响应）' }

# 只保留引用块，砍掉页脚
$cut = $text.IndexOf('CNKI知识服务')
if ($cut -gt 0) { $text = $text.Substring(0, $cut) }
$lines = $text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$lines | ForEach-Object { Write-Output $_ }
Write-Output "count: $($lines.Count)"
