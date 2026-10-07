param(
    [Parameter(Mandatory = $true)]
    [string]$Tab,

    [int]$WaitSeconds = 7
)

$ErrorActionPreference = 'Stop'

# 知网的「清除」按钮（a.btn-clearall）实测无效；已选列表其实存在 localStorage：
#   FileNameSNZKPT / batchNZKPT      已选条目的加密串
#   SelectFileNameSNZKPT             待导出的文件名
#   filenameIndexNZKPT               索引
# 清掉这几个键再刷新，已选就归零。多个结果页各自持有一份内存副本，
# 刷新/关闭它们之前不要在别处继续勾选，否则会把旧列表写回去。
$keys = @('FileNameSNZKPT', 'batchNZKPT', 'SelectFileNameSNZKPT', 'filenameIndexNZKPT')
$keyList = ($keys | ForEach-Object { "'$_'" }) -join ','

function Invoke-Js([string]$Script) {
    $raw = & agent-browser-cli exec --tab $Tab $Script | Out-String
    if ($LASTEXITCODE -ne 0) { throw "exec failed: $raw" }
    $obj = $raw | ConvertFrom-Json
    if (-not $obj.ok) { throw "exec not ok: $raw" }
    return $obj.result.js_return
}

$before = Invoke-Js 'return document.getElementById("selectCount")?document.getElementById("selectCount").textContent:"n/a"'
Write-Output "before: $before"

$clearJs = "[$keyList].forEach(k=>localStorage.removeItem(k)); return 'cleared'"
Invoke-Js $clearJs | Out-Null
Invoke-Js 'location.reload(); return "reloading"' | Out-Null
Start-Sleep -Seconds $WaitSeconds

$after = $null
for ($i = 1; $i -le 4; $i++) {
    $v = Invoke-Js 'return document.getElementById("selectCount")?document.getElementById("selectCount").textContent:"n/a"'
    if ($v -and $v -notmatch 'No response') { $after = $v; break }
    Start-Sleep -Seconds 2
}

Write-Output "after: $after"
if ($after -ne '0') {
    Write-Output 'warn: 已选没有归零，重跑一次这个脚本，或先关闭其它结果页标签再重跑'
    exit 1
}
Write-Output 'selection cleared'
