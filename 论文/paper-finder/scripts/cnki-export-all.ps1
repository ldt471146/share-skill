param(
    [Parameter(Mandatory = $true)]
    [string]$Tab,

    [string]$Filter = '',

    [string]$RawOut = '',

    [string]$OutFile = '',

    [int]$MaxRounds = 18,

    [int]$StableRounds = 2
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-Js([string]$Script, [string]$File) {
    $raw = if ($File) { & agent-browser-cli exec --tab $Tab --file $File | Out-String } else { & agent-browser-cli exec --tab $Tab $Script | Out-String }
    if ($LASTEXITCODE -ne 0) { throw "exec failed: $raw" }
    $obj = $raw | ConvertFrom-Json
    if (-not $obj.ok) { throw "exec not ok: $raw" }
    return $obj.result.js_return
}

function Get-Len {
    for ($i = 1; $i -le 3; $i++) {
        $v = Invoke-Js 'const el=document.getElementById("result"); return String((el.value||el.innerText||"").split(/\n(?=\[\d+\])/).length)' $null
        if ($v -and $v -notmatch 'No response') { return [int]$v }
        Start-Sleep -Milliseconds 800
    }
    return -1
}

# 导出页列表是滚动懒加载：必须「滚一次 → 等一会 → 看条数」，定时器突刺无效。
$prev = -1
$stable = 0
for ($i = 1; $i -le $MaxRounds; $i++) {
    Invoke-Js 'window.scrollTo(0, document.body.scrollHeight); return "scrolled"' $null | Out-Null
    Start-Sleep -Milliseconds 700
    $len = Get-Len
    if ($len -lt 0) { continue }
    if ($len -le $prev) { $stable++; if ($stable -ge $StableRounds) { break } } else { $stable = 0 }
    $prev = $len
}

if ($Filter) {
    Invoke-Js "window.__CNKI_FILTER = '$Filter'; 'ok'" $null | Out-Null
}

$dumpFile = Join-Path $here 'cnki-export-dump.js'
$json = $null
for ($i = 1; $i -le 3; $i++) {
    $v = Invoke-Js $null $dumpFile
    if ($v -and $v -notmatch 'No response') { $json = $v; break }
    Start-Sleep -Seconds 2
}
if (-not $json) { throw '导出页没响应（exec 超时），重跑一次即可' }

$data = $json | ConvertFrom-Json
Write-Output "export_total: $($data.total)"
Write-Output "export_kept: $($data.kept)"

if (-not $data.blocks) { return }

if (-not $RawOut) { $RawOut = Join-Path $env:TEMP 'cnki-raw.txt' }
if (-not $OutFile) { $OutFile = Join-Path $env:TEMP 'cnki-clean.txt' }
$data.blocks -join "`n" | Set-Content -LiteralPath $RawOut -Encoding UTF8
& pwsh -NoProfile -File (Join-Path $here 'clean-citation.ps1') -Path $RawOut -OutFile $OutFile | Out-Null
Get-Content -LiteralPath $OutFile -Encoding UTF8
