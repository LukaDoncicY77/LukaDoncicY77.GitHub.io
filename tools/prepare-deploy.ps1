[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$blogRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$hexoCmd = Join-Path $blogRoot 'node_modules\.bin\hexo.cmd'
$configPath = Join-Path $blogRoot '_config.yml'
$sourceRoot = Join-Path $blogRoot 'source'
$publicRoot = Join-Path $blogRoot 'public'

if (-not (Test-Path -LiteralPath $hexoCmd -PathType Leaf)) {
    throw "Local Hexo executable is missing: $hexoCmd"
}

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Hexo configuration is missing: $configPath"
}

$configText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
if ($configText -notmatch '(?m)^\s*repository:\s*https://github\.com/LukaDoncicY77/LukaDoncicY77\.GitHub\.io\.git\s*(?:#.*)?$') {
    throw 'The deploy repository in _config.yml is not the approved GitHub Pages repository.'
}
if ($configText -notmatch '(?m)^\s*branch:\s*main\s*(?:#.*)?$') {
    throw 'The deploy branch in _config.yml is not main.'
}

$sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force)
$oversizedSource = @($sourceFiles | Where-Object { $_.Length -ge 100MB })
if ($oversizedSource.Count -gt 0) {
    $paths = $oversizedSource.FullName -join [Environment]::NewLine
    throw "Source contains files at or above GitHub's 100 MB per-file limit:`n$paths"
}

$sensitiveSource = @($sourceFiles | Where-Object {
    $_.Name -match '(?i)(cookie|credential|account_keys|sessionid|ttwid|odin_tt|passport)' -or
    $_.Extension -match '(?i)^\.(pem|key|pfx|sqlite|sqlite3)$'
})
if ($sensitiveSource.Count -gt 0) {
    $paths = $sensitiveSource.FullName -join [Environment]::NewLine
    throw "Potentially private credential/database files were found under source:`n$paths"
}

Push-Location $blogRoot
try {
    & $hexoCmd clean
    if ($LASTEXITCODE -ne 0) {
        throw "Hexo clean failed with exit code $LASTEXITCODE."
    }

    & $hexoCmd generate
    if ($LASTEXITCODE -ne 0) {
        throw "Hexo generate failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

foreach ($required in @('index.html', 'columns\index.html')) {
    $requiredPath = Join-Path $publicRoot $required
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Generated site is missing required output: $requiredPath"
    }
}

$publicFiles = @(Get-ChildItem -LiteralPath $publicRoot -Recurse -File -Force)
$emptyHtmlFiles = @($publicFiles | Where-Object {
    $_.Extension -eq '.html' -and $_.Length -eq 0
})

if ($emptyHtmlFiles.Count -gt 0) {
    $paths = $emptyHtmlFiles.FullName -join [Environment]::NewLine
    throw "Generated site contains zero-byte HTML files. Deployment stopped:`n$paths"
}
$oversizedPublic = @($publicFiles | Where-Object { $_.Length -ge 100MB })
if ($oversizedPublic.Count -gt 0) {
    $paths = $oversizedPublic.FullName -join [Environment]::NewLine
    throw "Generated site contains files at or above GitHub's 100 MB per-file limit:`n$paths"
}

$forbiddenSegments = @(
    'Backups',
    'Douyin-archive',
    'Personal-context',
    'Qzone-archive',
    'WeChat-archive',
    'private',
    'quarantine'
)
$forbiddenOutput = @($publicFiles | Where-Object {
    $relative = $_.FullName.Substring($publicRoot.Length).TrimStart('\', '/')
    $segments = $relative -split '[\\/]'
    @($segments | Where-Object { $forbiddenSegments -contains $_ }).Count -gt 0
})
if ($forbiddenOutput.Count -gt 0) {
    $paths = $forbiddenOutput.FullName -join [Environment]::NewLine
    throw "Generated site contains forbidden private/archive path segments:`n$paths"
}

$totalBytes = ($publicFiles | Measure-Object Length -Sum).Sum
$htmlCount = @($publicFiles | Where-Object { $_.Extension -eq '.html' }).Count
Write-Host ''
Write-Host 'Local deploy preparation passed.' -ForegroundColor Green
Write-Host "Generated files: $($publicFiles.Count)"
Write-Host "HTML files: $htmlCount"
Write-Host ("Generated size: {0:N2} MiB" -f ($totalBytes / 1MB))
Write-Host 'Nothing was uploaded.' -ForegroundColor Yellow
