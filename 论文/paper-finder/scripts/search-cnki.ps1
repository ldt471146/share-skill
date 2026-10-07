param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Chinese', 'Foreign')]
    [string]$Database,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Title', 'Subject', 'Doi')]
    [string]$Field,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Query
)

$term = [Uri]::EscapeDataString($Query.Trim())
if ($Database -eq 'Chinese') {
    if ($Field -eq 'Doi') {
        throw 'Chinese DOI search is not supported by this helper; use Title or Subject.'
    }
    $url = "https://kns.cnki.net/kns8s/defaultresult/index?kw=$term"
} else {
    switch ($Field) {
        'Title' { $fieldCode = 'TI'; $fieldName = '%E9%A2%98%E5%90%8D' }
        'Subject' { $fieldCode = 'SUW'; $fieldName = '%E4%B8%BB%E9%A2%98%E8%AF%8D' }
        'Doi' { $fieldCode = 'DOI'; $fieldName = 'DOI' }
    }
    $url = "https://scholar.cnki.net/homeSearch?sw=$fieldCode&text=$fieldName&sw-input=$term&operator=TOPRANK"
}

$openOutput = (& agent-browser-cli open $url | Out-String)
$opened = $null
if ($LASTEXITCODE -eq 0) {
    $opened = $openOutput | ConvertFrom-Json
}
if (-not $opened.ok -or -not $opened.result.opened_tab_id) {
    $startup = Join-Path $env:USERPROFILE '.agent-browser-cli/start-fast.ps1'
    if (-not (Test-Path -LiteralPath $startup)) {
        throw "CNKI tab was not opened and browser startup script is missing: $openOutput"
    }
    $null = (& pwsh -NoProfile -File $startup 'https://www.cnki.net/' | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Browser startup failed: $openOutput"
    }
    $openOutput = (& agent-browser-cli open $url | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "agent-browser-cli open failed: $openOutput"
    }
    $opened = $openOutput | ConvertFrom-Json
    if (-not $opened.ok -or -not $opened.result.opened_tab_id) {
        throw "CNKI tab was not opened: $openOutput"
    }
}

$tabId = $opened.result.opened_tab_id
Write-Output "tab_id: $tabId"
Write-Output "search_url: $url"
