param(
    [string]$Path = '',

    [string]$Text = '',

    [string]$OutFile = ''
)

$ErrorActionPreference = 'Stop'

# CNKI's on-page citation text carries display spaces around half-width punctuation
# (", " "[J]. " ": " "[C]// "); the official GB/T 7714-2025 text has none.
# Only spaces adjacent to half-width punctuation are removed. Full-width punctuation,
# CJK characters, spaces inside English words and line structure stay untouched.
# Prefer -Path (a UTF-8 file) or -Text: piping CJK through a child process can mangle
# it, because the pipe is encoded with the console codepage.
$raw = if ($Path) {
    Get-Content -LiteralPath $Path -Encoding UTF8 -Raw
} elseif ($Text) {
    $Text
} else {
    $input | Out-String
}

$cleaned = ($raw -split "`r?`n") | ForEach-Object {
    ($_ -replace '[ \t\u3000]+([.,:;()\[\]/])', '$1') -replace '([.,:;()\[\]/])[ \t\u3000]+', '$1'
}

$result = ($cleaned -join "`n").TrimEnd("`n")

if ($OutFile) {
    Set-Content -LiteralPath $OutFile -Value $result -Encoding UTF8
    Write-Output "written: $OutFile"
} else {
    Write-Output $result
}
