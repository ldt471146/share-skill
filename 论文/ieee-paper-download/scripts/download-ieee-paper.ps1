<#
.SYNOPSIS
    One-click download of a paper PDF from IEEE Xplore.
.DESCRIPTION
    IEEE Xplore is protected by a WAF (aws-waf-token JS challenge + CloudFront signed
    cookies + APM scripts). Direct HTTP requests to PDF URLs are blocked. This script
    uses the real Chrome session (via agent-browser-cli) to: open the document page,
    capture the real ielx8 PDF URL from network monitoring, export the session cookies,
    then replay the download with a full browser request header set.

    This is the only verified-working path. See the skill SKILL.md for the failure list.

.EXAMPLE
    pwsh -File download-ieee-paper.ps1 -ArticleId 11505776 -OutPath "$env:USERPROFILE\Desktop\paper.pdf"

.EXAMPLE
    pwsh -File download-ieee-paper.ps1 -DocumentUrl "https://ieeexplore.ieee.org/document/11505776"
#>
param(
    [string]$ArticleId = "",
    [string]$DocumentUrl = "",
    [string]$OutPath = "",
    [switch]$NoOpen,
    [int]$WaitSeconds = 6,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

function Get-JsonFromCli {
    param([string]$RawText)
    $text = ($RawText | Out-String).Trim()
    if (-not $text) { throw "Empty output from agent-browser-cli" }
    return $text | ConvertFrom-Json
}

# ---- resolve article id -------------------------------------------------
if ($DocumentUrl) {
    if ($DocumentUrl -match "/document/(\d+)") { $ArticleId = $Matches[1] }
    elseif ($DocumentUrl -match "arnumber=(\d+)") { $ArticleId = $Matches[1] }
    else { throw "Cannot extract article id from URL: $DocumentUrl" }
}
if (-not $ArticleId) { throw "Provide -ArticleId or -DocumentUrl" }
$docUrl = "https://ieeexplore.ieee.org/document/$ArticleId"

if (-not $OutPath) {
    $OutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "paper_$ArticleId.pdf"
}
$OutPath = [System.IO.Path]::GetFullPath($OutPath)
$OutDir = [System.IO.Path]::GetDirectoryName($OutPath)
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

Write-Host "[1/6] Locating a browser tab..."
$tabId = ""
try {
    $tabsJson = Get-JsonFromCli (agent-browser-cli tabs)
    $tabCount = [int]$tabsJson.result.metadata.tabs_count
} catch {
    $tabCount = 0
}

if ($tabCount -gt 0 -and $NoOpen) {
    $tabId = [string]$tabsJson.result.metadata.tabs[0].id
    Write-Host "      Reusing existing tab $tabId (navigating to document page)..."
    agent-browser-cli exec --tab $tabId "window.open('$docUrl','_self'); return 'nav';" | Out-Null
    Start-Sleep -Seconds $WaitSeconds
}
else {
    if ($tabCount -eq 0) {
        Write-Host "      No browser available - starting Chrome with bridge extension..."
        $chromePath = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe' -ErrorAction SilentlyContinue).'(default)'
        if (-not $chromePath) { $chromePath = 'C:\Program Files\Google\Chrome\Application\chrome.exe' }
        if (-not (Test-Path $chromePath)) { throw "Chrome not found at $chromePath" }
        $extDir = "$env:USERPROFILE\.agent-browser-cli\extension\tmwd_cdp_bridge"
        Start-Process -FilePath $chromePath -ArgumentList "--load-extension=$extDir", "--disable-blink-features=AutomationControlled", $docUrl
        Start-Sleep -Seconds 12
    }
    $openJson = Get-JsonFromCli (agent-browser-cli open $docUrl)
    $openTabId = if ($openJson.result.opened_tab_id) { $openJson.result.opened_tab_id } else { $openJson.opened_tab_id }
    if (-not $openTabId) { throw "agent-browser-cli open failed: $($openJson | ConvertTo-Json -Compress -Depth 6)" }
    $tabId = [string]$openTabId
    Write-Host "      Opened document page in tab $tabId"
    Start-Sleep -Seconds $WaitSeconds
}
if (-not $tabId) { throw "No usable tab" }

# ---- capture PDF URL with retry (WAF may return ?denied= on first attempts) ------
$pdfUrl = ""
$maxTries = 3
for ($try = 1; $try -le $maxTries -and -not $pdfUrl; $try++) {
    # IEEE pages run a JS challenge + MathJax on load; wait until the Download PDF
    # button actually exists before clicking (up to 30s), otherwise the click no-ops.
    $btnReady = $false
    for ($w = 0; $w -lt 10 -and -not $btnReady; $w++) {
        Start-Sleep -Seconds 3
        try {
            $readyCheck = agent-browser-cli exec --tab $tabId 'return (document.querySelector("a[class*=\"downloadPdf\"]") !== null) || ([...document.querySelectorAll("a")].some(a => /download\s*pdf/i.test(a.textContent||"")));'
            $btnReady = (($readyCheck | Out-String) -match 'true')
        } catch { }
    }
    if (-not $btnReady) {
        Write-Host "      Download button not found after waiting - reloading page..."
        agent-browser-cli exec --tab $tabId "window.open('$docUrl','_self'); return 'reload';" | Out-Null
        Start-Sleep -Seconds 6
        continue
    }

    Write-Host "[2/6] (try $try/$maxTries) Starting network monitoring on tab $tabId..."
    $netStartOk = $false
    for ($s = 1; $s -le 3 -and -not $netStartOk; $s++) {
        try {
            $nsJson = Get-JsonFromCli (agent-browser-cli network start --tab $tabId)
            $netStartOk = ($nsJson.result.status -eq "started") -or ($nsJson.result.ok -eq $true)
        } catch {
            Start-Sleep -Seconds 2
        }
        if (-not $netStartOk) { Start-Sleep -Seconds 2 }
    }
    if (-not $netStartOk) {
        agent-browser-cli network stop --tab $tabId | Out-Null
        Start-Sleep -Seconds 2
        agent-browser-cli network start --tab $tabId | Out-Null
    }
    Start-Sleep -Seconds 2

    Write-Host "[3/6] Clicking Download PDF button..."
    $clickJs = '(function(){ const candidates = [...document.querySelectorAll("a")].filter(a => /download\s*pdf/i.test(a.textContent||"")); if (candidates.length) { candidates[0].click(); return "clicked:by-text"; } const byClass = document.querySelector("a[class*=\"downloadPdf\"]"); if (byClass) { byClass.click(); return "clicked:by-class"; } const byHref = document.querySelector("a[href*=\"stamp.jsp\"]"); if (byHref) { byHref.click(); return "clicked:by-href"; } return "not-found"; })()'
    $clickRes = agent-browser-cli exec --tab $tabId $clickJs
    Write-Host "      Click result: $($clickRes | Out-String | Select-Object -First 1)"

    Write-Host "[4/6] Capturing real PDF URL from network log..."
    for ($i = 0; $i -lt 12 -and -not $pdfUrl; $i++) {
        Start-Sleep -Seconds 3
        try {
            $netJson = Get-JsonFromCli (agent-browser-cli network list --tab $tabId)
            $reqs = @($netJson.result.requests)
            $pdfReq = $reqs | Where-Object { ($_.mimeType -eq "application/pdf" -or $_.url -like "*ielx8*") -and $_.url -like "*ieeexplore.ieee.org*" } | Select-Object -First 1
            if ($pdfReq) { $pdfUrl = [string]$pdfReq.url }
        } catch { }
    }

    if (-not $pdfUrl) {
        # Distinguish "subscription required" from "WAF denied".
        # NOTE: must use the subscription-wall dialog's own copy ("Access Through Your
        # Institution" / "Not a subscriber?") - generic words like "subscribe"/"purchase"
        # appear in every IEEE page's navbar and would cause false positives.
        $subCheck = agent-browser-cli exec --tab $tabId 'const t = document.body.innerText || ""; return /(access through your institution|not a subscriber\?|sign in with username and password)/i.test(t) ? "subscribed-wall" : "waf";'
        $subResult = ($subCheck | Out-String)
        if ($subResult -match 'subscribed-wall') {
            try { agent-browser-cli network stop --tab $tabId | Out-Null } catch { }
            throw "This paper is NOT open access - IEEE requires institutional subscription or purchase (a sign-in/purchase wall is displayed). The skill only works for Open Access / CC BY / institution-licensed papers. If your school has access, sign in via institutional login in Chrome first, then rerun."
        }
        Write-Host "      Not captured yet - WAF may have denied the click. Reloading document page and retrying..."
        try { agent-browser-cli network stop --tab $tabId | Out-Null } catch { }
        agent-browser-cli exec --tab $tabId "window.open('$docUrl','_self'); return 'reload';" | Out-Null
        Start-Sleep -Seconds 6
    }
}
if (-not $pdfUrl) {
    try { agent-browser-cli network stop --tab $tabId | Out-Null } catch { }
    throw "PDF URL was not captured after $maxTries tries. The WAF JS challenge may need solving in the real browser first - open the document page in Chrome manually, wait a few seconds, then rerun the script."
}
Write-Host "      PDF URL: $pdfUrl"

Write-Host "[5/6] Exporting session cookies and downloading..."
$cookiesJson = Get-JsonFromCli (agent-browser-cli exec '{"cmd":"cookies","url":"https://ieeexplore.ieee.org/"}')
$cookieArr = @($cookiesJson.result.js_return)
$cookieStr = ($cookieArr | ForEach-Object { "$($_.name)=$($_.value)" }) -join '; '

$headers = @{
    'User-Agent'               = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    'Referer'                  = $docUrl
    'Cookie'                   = $cookieStr
    'Accept'                   = 'application/pdf,*/*'
    'Sec-Fetch-Dest'           = 'document'
    'Sec-Fetch-Mode'           = 'navigate'
    'Sec-Fetch-Site'           = 'same-origin'
    'Sec-Fetch-User'           = '?1'
    'Upgrade-Insecure-Requests' = '1'
}
Invoke-WebRequest -Uri $pdfUrl -Headers $headers -OutFile $OutPath -TimeoutSec $TimeoutSeconds

Write-Host "[6/6] Verifying PDF..."
$bytes = [System.IO.File]::ReadAllBytes($OutPath)
$isPdf = $bytes.Length -gt 102400 -and [System.Text.Encoding]::ASCII.GetString($bytes[0..3]) -eq '%PDF'
if (-not $isPdf) {
    Remove-Item $OutPath -Force
    throw "Download failed - file is not a valid PDF (${($bytes.Length)} bytes). WAF blocked the request; rerun the script once more (reopening the page solves the JS challenge)."
}

try { agent-browser-cli network stop --tab $tabId | Out-Null } catch { }
Write-Host ""
Write-Host "SUCCESS: $OutPath"
Write-Host "         Size: $([Math]::Round($bytes.Length / 1MB, 2)) MB ($($bytes.Length) bytes)"
