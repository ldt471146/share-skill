#!/usr/bin/env pwsh
<#
.SYNOPSIS
  模糊检索：多词扩检 → 合并去重 → 主题/类型过滤 → 排序 → 输出 URL 列表。

.DESCRIPTION
  实现 SKILL.md「模糊检索（默认策略）」那一节的标准流程。用户给一个主题词时，
  用本脚本一次跑完，产出可直接喂给 `cnki batch` 的 URL 列表。

  之所以要多词：单词命中动辄上万条，相关度排序会把行业新闻、教学改革类顶到前面，
  真正的系统实现类论文被淹没。多词扩检 + 过滤才能把它们捞出来。

.PARAMETER Topic
  主题关键词（正则，用于过滤题名）。例：'文旅|旅游|景区|非遗'

.PARAMETER Query
  扩检检索词，可重复。例：-Query '旅游 系统 设计与实现' -Query '文旅 平台'

.PARAMETER TypeKeyword
  技术实现类关键词（正则），命中的排前面。默认覆盖常见技术栈。

.PARAMETER From / To
  年份范围（含）。

.PARAMETER TopN
  最终取前 N 篇（默认 10）。注意不要写成 $top 之类的局部变量：
  PowerShell 变量名大小写不敏感，$top 与 [int]$TopN 无关但与 [int]$Top 同体，
  给 [int] 约束的变量赋数组会直接报 "无法将 Object[] 转换为 Int32"。

.PARAMETER DelaySec
  每次检索之间的间隔秒数（默认 11）。防验证码，别调太小。

.PARAMETER OutUrls
  URL 列表输出路径（默认 <tmp>/fuzzy-urls.txt）。

.PARAMETER OutJson
  合并后的原始元数据输出路径。

.EXAMPLE
  ./fuzzy-search.ps1 -Topic '文旅|旅游|景区|非遗' -From 2023 -To 2026 `
    -Query '旅游 系统 设计与实现' -Query '文旅 平台' -Query '智慧旅游 系统' `
    -Query '旅游 推荐系统','文化旅游 数字化 平台' -TopN 10
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Topic,
    [Parameter(Mandatory = $true)][string[]]$Query,
    [string]$TypeKeyword = '系统|平台|小程序|网站|软件|设计|实现|开发|架构|Spring|Vue|Java|Web|推荐',
    [int]$From = 0,
    [int]$To = 0,
    [int]$TopN = 10,
    [int]$DelaySec = 11,
    [int]$Size = 30,
    [string]$OutUrls = "",
    [string]$OutJson = "",
    [switch]$IncludeTheses,
    [switch]$IncludeNewspapers
)

$ErrorActionPreference = 'Stop'

function Strip-Spaces([string]$s) {
    if ($null -eq $s) { return "" }
    return ($s -replace '\s+', '').Trim()
}

if (-not $OutUrls) {
    $OutUrls = Join-Path $env:TEMP 'fuzzy-urls.txt'
}
if (-not $OutJson) {
    $OutJson = Join-Path $env:TEMP 'fuzzy-pool.json'
}

# ---- 1. 多词扩检 ----------------------------------------------------------
$all = @()
foreach ($q in $Query) {
    $cliArgs = @('search', $q, '--field=topic', '--format=json', "--size=$Size", '--sort=relevance')
    if ($From -gt 0) { $cliArgs += "--from=$From" }
    if ($To -gt 0) { $cliArgs += "--to=$To" }

    $raw = & cnki @cliArgs 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        try {
            $j = $raw | ConvertFrom-Json
            Write-Host ("  [{0}] hits={1} got={2}" -f $q, $j.total_hits, $j.fetched)
            $all += $j.results
        } catch {
            Write-Warning "  [$q] JSON 解析失败"
        }
    } else {
        Write-Warning "  [$q] exit=$LASTEXITCODE (假空或验证码；稍后重试该词)"
    }

    if ($q -ne $Query[-1]) { Start-Sleep -Seconds $DelaySec }
}

if ($all.Count -eq 0) {
    throw "所有检索词都无结果；可能是风控或检索词过窄。等 60s 后重试。"
}

# ---- 2. 合并去重（先去空格，规避 CNKI 高亮残留） --------------------------
$seen = @{}
$pool = @()
foreach ($r in $all) {
    $key = Strip-Spaces $r.title
    if ($key -and -not $seen.ContainsKey($key)) {
        $seen[$key] = $true
        $pool += $r
    }
}
Write-Host ("合并去重后: {0} 条" -f $pool.Count)

# ---- 3/4. 主题 + 类型过滤 -------------------------------------------------
$filtered = $pool | Where-Object {
    $t = Strip-Spaces $_.title
    if ($t -notmatch $Topic) { return $false }

    $src = "$($_.source)"
    if (-not $IncludeTheses -and $src -match '大学$|学院$') { return $false }
    if (-not $IncludeNewspapers -and $src -match '报$|日报$|商报$|晚报$') { return $false }
    return $true
}
Write-Host ("主题+类型过滤后: {0} 条" -f $filtered.Count)

if ($filtered.Count -eq 0) {
    throw "过滤后为空；放宽 -Topic 或加 -IncludeTheses/-IncludeNewspapers。"
}

# ---- 5. 排序：技术实现类优先，再按被引降序 --------------------------------
$ranked = $filtered | Sort-Object -Property `
    @{ Expression = { if ((Strip-Spaces $_.title) -match $TypeKeyword) { 0 } else { 1 } } }, `
    @{ Expression = { [int]$_.cited }; Descending = $true }, `
    @{ Expression = { [int]$_.year }; Descending = $true }

$selected = @($ranked | Select-Object -First $TopN)

# ---- 6. 输出 --------------------------------------------------------------
$selected | ForEach-Object { $_.url } | Set-Content -LiteralPath $OutUrls -Encoding UTF8
$ranked | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutJson -Encoding UTF8

Write-Host ""
Write-Host "选中 $($selected.Count) 篇："
$i = 0
foreach ($p in $selected) {
    $i++
    Write-Host ("  {0,2}. cited={1} {2} | {3} | {4}" -f $i, $p.cited, $p.year, $p.source, $p.title)
}
Write-Host ""
Write-Host "URL 列表 -> $OutUrls"
Write-Host "元数据   -> $OutJson"
Write-Host ""
Write-Host "下一步（批量出引用，注意 12s 间隔）："
Write-Host "  cnki batch --from-file `"$OutUrls`" --headless --format=citation --delay 12s"
