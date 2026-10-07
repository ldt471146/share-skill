# Regression tests for scripts/clean-citation.ps1.
# The two cases marked 用户确认 come from real CNKI output the user corrected by hand.
# Note: PowerShell 7 treats ’ as a quote character, so smart quotes are injected via $SQ.
$ErrorActionPreference = 'Stop'

$cleaner = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/clean-citation.ps1'
$SQ = [char]0x2019
$failures = @()
$caseNo = 0
$tmpDir = Join-Path $env:TEMP ('paper-finder-clean-tests-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null

# File-based round trip: piping CJK through a child process mangles it.
function Get-Cleaned([string]$Text) {
    $script:caseNo++
    $in = Join-Path $tmpDir "in-$($script:caseNo).txt"
    $out = Join-Path $tmpDir "out-$($script:caseNo).txt"
    Set-Content -LiteralPath $in -Value $Text -Encoding UTF8
    & pwsh -NoProfile -File $cleaner -Path $in -OutFile $out | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "clean-citation.ps1 failed on $in" }
    return (Get-Content -LiteralPath $out -Encoding UTF8 -Raw).TrimEnd("`r", "`n")
}

function Assert-Equal([string]$Name, [string]$Actual, [string]$Expected) {
    if ($Actual -ne $Expected) {
        $script:failures += "$Name`n  expected: $Expected`n  actual:   $Actual"
        Write-Output "FAIL $Name"
    } else {
        Write-Output "ok   $Name"
    }
}

function Assert-Match([string]$Name, [string]$Actual, [string]$Pattern) {
    if ($Actual -notmatch $Pattern) {
        $script:failures += "$Name`n  expected pattern: $Pattern`n  actual: $Actual"
        Write-Output "FAIL $Name"
    } else {
        Write-Output "ok   $Name"
    }
}

# 1. 用户确认：会议论文（GB/T 7714-2025，无展示空格）
$in1 = "党悦文,赵东明,卢淼,等. 基于具身智能的智慧文旅多机器人交互服务系统研究[C]// 天津市电子学会. 第四十届中国（天津）2026${SQ}IT、网络、信息技术、电子、仪器仪表创新学术会议论文集. 2026: 333-336. DOI:10.26914/c.cnkihy.2026.051611."
$want1 = "党悦文,赵东明,卢淼,等.基于具身智能的智慧文旅多机器人交互服务系统研究[C]//天津市电子学会.第四十届中国（天津）2026${SQ}IT、网络、信息技术、电子、仪器仪表创新学术会议论文集.2026:333-336.DOI:10.26914/c.cnkihy.2026.051611."
Assert-Equal '用户确认-会议论文' (Get-Cleaned $in1) $want1

# 2. 用户确认：期刊论文（卷期页码）
$in2 = '周海霞,张燕,廉吉全. 长征沿线文化—旅游系统适配驱动文旅融合发展的时空演变与机理 [J]. 地理科学进展, 2025, 44 (9): 1883-1900.'
$want2 = '周海霞,张燕,廉吉全.长征沿线文化—旅游系统适配驱动文旅融合发展的时空演变与机理[J].地理科学进展,2025,44(9):1883-1900.'
Assert-Equal '用户确认-期刊论文' (Get-Cleaned $in2) $want2

# 3. 学位论文 + DOI
$in3 = '臧传润. 基于知识图谱的黄河文旅资源问答系统设计与实现[D]. 山东大学, 2025. DOI:10.27272/d.cnki.gshdu.2025.005929.'
$want3 = '臧传润.基于知识图谱的黄河文旅资源问答系统设计与实现[D].山东大学,2025.DOI:10.27272/d.cnki.gshdu.2025.005929.'
Assert-Equal '学位论文-DOI' (Get-Cleaned $in3) $want3

# 4. 西文条目：标点旁空格要去掉，英文词间空格要保留
$in4 = 'Khan R A ,Furuoka F ,Rasiah R . What drives users to continue using second-hand trading platforms? An integrated framework [J]. Italian Journal of Marketing, 2026, 2026 (1): 18-18.'
$out4 = Get-Cleaned $in4
Assert-Match '西文-标点旁无空格' $out4 'framework\[J\]\.Italian Journal of Marketing,2026,2026\(1\):18-18\.'
Assert-Match '西文-词间空格保留' $out4 'What drives users to continue using second-hand trading platforms\?'

# 5. 全角标点、中文与行结构不受影响
$in5 = "第四十届中国（天津）2026${SQ}IT、网络`n中文 空格保留 [J] ."
$out5 = Get-Cleaned $in5
Assert-Match '全角与中文不动' $out5 "第四十届中国（天津）2026${SQ}IT、网络"
Assert-Match '中文间空格不动' $out5 '中文 空格保留'
Assert-Match '行数保持' $out5 "网络`n中文 空格保留\[J\]\."

Remove-Item -LiteralPath $tmpDir -Recurse -Force

if ($failures.Count -gt 0) {
    Write-Output ''
    Write-Output "FAILED: $($failures.Count)"
    $failures | ForEach-Object { Write-Output $_ }
    exit 1
}

Write-Output ''
Write-Output 'all clean-citation tests passed'
