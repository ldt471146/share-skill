param(
    [Parameter(Mandatory = $true)]
    [string]$Tab,

    [int]$WaitMs = 900,

    [int]$PollSeconds = 15
)

$ErrorActionPreference = 'Stop'

function Invoke-Js([string]$Js) {
    $raw = (& agent-browser-cli exec --tab $Tab --file $Js | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "agent-browser-cli exec failed: $raw" }
    $obj = $raw | ConvertFrom-Json
    if (-not $obj.ok) { throw "exec not ok: $raw" }
    return $obj.result.js_return
}

function Send-Mouse([string]$Type, [int]$X, [int]$Y, [string]$Button) {
    $json = '{"cmd":"cdp","tabId":' + $Tab + ',"method":"Input.dispatchMouseEvent","params":{"type":"' + $Type + '","x":' + $X + ',"y":' + $Y + ',"button":"' + $Button + '","clickCount":1}}'
    $out = (& agent-browser-cli exec $json | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "cdp $Type failed: $out" }
}

function Move-At([object]$Point) { Send-Mouse 'mouseMoved' $Point.x $Point.y 'none' }

function Click-At([object]$Point) {
    Move-At $Point
    Send-Mouse 'mousePressed' $Point.x $Point.y 'left'
    Send-Mouse 'mouseReleased' $Point.x $Point.y 'left'
}

# The batch bar is hover-driven: only real CDP mouse events open it. JS .click() does nothing.
$tmp = Join-Path $env:TEMP 'cnki-export-rect.js'
$scrollScript = Join-Path $env:TEMP 'cnki-export-scroll.js'
$rectScript = $tmp

@'
const menu = [...document.querySelectorAll('a')].find(a => (a.textContent || '').trim() === '导出与分析');
if (!menu) return 'no-menu';
const r = menu.getBoundingClientRect();
window.scrollTo(0, Math.max(0, window.scrollY + r.top - 160));   // clear of the sticky header
return 'scrolled';
'@ | Set-Content -LiteralPath $scrollScript -Encoding UTF8

@'
const center = (e) => {
  const b = e.getBoundingClientRect();
  return { x: Math.round(b.x + b.width / 2), y: Math.round(b.y + b.height / 2), inView: b.top >= 40 && b.bottom <= window.innerHeight - 10 && b.width > 0 };
};
const byText = (t) => [...document.querySelectorAll('a')].find(a => (a.textContent || '').trim() === t);
const out = byText('导出文献');
const gbt = document.querySelector('a[exporttype="GBTREFER"]');
return JSON.stringify({
  menu: byText('导出与分析') ? center(byText('导出与分析')) : null,
  outLink: out ? center(out) : null,
  gbt: gbt ? center(gbt) : null
});
'@ | Set-Content -LiteralPath $rectScript -Encoding UTF8

function Get-Rects {
    if ((Invoke-Js $scrollScript) -eq 'no-menu') { throw '未找到「导出与分析」：确认当前标签是 kns8s 检索结果页' }
    Start-Sleep -Milliseconds 250
    return (Invoke-Js $rectScript) | ConvertFrom-Json
}

$rect = Get-Rects
if (-not $rect.menu) { throw '「导出与分析」不可读：先确认已有勾选、批量操作条存在' }
if (-not $rect.menu.inView) { throw "「导出与分析」不在视口内（y=$($rect.menu.y)）：页面没滚到位或因弹层遮挡，先手工确认批量操作条可见" }

Send-Mouse 'mouseMoved' 0 0 'none'   # warm up the CDP session before the first real click
Start-Sleep -Milliseconds 200
Click-At $rect.menu
Start-Sleep -Milliseconds $WaitMs

$rect = Get-Rects
if (-not $rect.outLink) { throw '「导出文献」未出现：导出与分析菜单没有展开' }
Move-At $rect.outLink
Start-Sleep -Milliseconds $WaitMs

$rect = Get-Rects
if (-not $rect.gbt) { throw '「GB/T 7714-2025 格式引文」未出现：二级菜单没有展开' }
Click-At $rect.gbt

$deadline = (Get-Date).AddSeconds($PollSeconds)
$exportUrl = $null
$exportTab = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700
    $tabs = (agent-browser-cli tabs | Out-String | ConvertFrom-Json).result.metadata.tabs
    $hit = $tabs | Where-Object { $_.url -like '*dm8/manage/export.html*' } | Select-Object -First 1
    if ($hit) { $exportUrl = $hit.url; $exportTab = $hit.tab_id; break }
}

if (-not $exportUrl) { throw "导出页未在 $PollSeconds 秒内打开（可加大 -PollSeconds）" }

Write-Output "export_tab: $exportTab"
Write-Output "export_url: $exportUrl"
