param(
    [string]$RepoRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path)
)
if (Test-Path (Join-Path $RepoRoot 'scripts')) { $RepoRoot = Split-Path -Parent (Join-Path $RepoRoot 'scripts') }

$ErrorActionPreference = 'Stop'
$categories = @()

foreach ($cat in (Get-ChildItem $RepoRoot -Directory | Where-Object { $_.Name -notin @('scripts', '.git') } | Sort-Object Name)) {
    $skills = @()
    foreach ($s in (Get-ChildItem $cat.FullName -Directory | Sort-Object Name)) {
        $skillMd = Join-Path $s.FullName 'SKILL.md'
        $name = $s.Name
        $desc = ''
        if (Test-Path $skillMd) {
            foreach ($line in (Get-Content $skillMd -TotalCount 40)) {
                if ($line -match '^name:\s*(.+)$') { $name = $Matches[1].Trim(); continue }
                if ($line -match '^description:\s*(.+)$') { $desc = $Matches[1].Trim().Trim('"', "'"); break }
            }
        }
        $skills += [ordered]@{
            name        = $name
            path        = "$($cat.Name)/$($s.Name)"
            description = $desc
            files       = (Get-ChildItem $s.FullName -Recurse -File | Measure-Object).Count
        }
    }
    $categories += [ordered]@{
        category = $cat.Name
        count    = $skills.Count
        skills   = $skills
    }
}

$index = [ordered]@{
    name       = 'share-skill'
    updated_at = (Get-Date).ToString('yyyy-MM-dd')
    total      = ($categories | ForEach-Object { $_.count } | Measure-Object -Sum).Sum
    categories = $categories
}

$index | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $RepoRoot 'skills.json') -Encoding UTF8
Write-Output "skills.json 已生成：$($index.total) 个 skills / $($categories.Count) 个类别"
