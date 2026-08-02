[CmdletBinding()]
param(
    [switch]$Approve
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Approve) {
    throw 'Publishing is blocked. Run this script again with -Approve only after the user explicitly approves uploading the current public content.'
}

$blogRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$workspaceRoot = Split-Path -Parent $blogRoot
$prepareScript = Join-Path $PSScriptRoot 'prepare-deploy.ps1'
$hexoCmd = Join-Path $blogRoot 'node_modules\.bin\hexo.cmd'
$repository = 'https://github.com/LukaDoncicY77/LukaDoncicY77.GitHub.io.git'
$portableGh = Join-Path $workspaceRoot '.tools\gh-2.97.0\bin\gh.exe'

Push-Location $blogRoot
try {
    $insideGit = (& git rev-parse --is-inside-work-tree 2>$null)
    if ($LASTEXITCODE -ne 0 -or $insideGit -ne 'true') {
        throw 'Blog source is not a Git working tree.'
    }

    $sourceStatus = @(& git status --porcelain --untracked-files=all)
    if ($sourceStatus.Count -gt 0) {
        throw "Blog source has uncommitted changes. Review and commit them before publishing:`n$($sourceStatus -join [Environment]::NewLine)"
    }
}
finally {
    Pop-Location
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $prepareScript
if ($LASTEXITCODE -ne 0) {
    throw "Local deploy preparation failed with exit code $LASTEXITCODE."
}

$ghPath = $null
if (Test-Path -LiteralPath $portableGh -PathType Leaf) {
    $ghPath = $portableGh
}
else {
    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -ne $ghCommand) {
        $ghPath = $ghCommand.Source
    }
}
if ([string]::IsNullOrWhiteSpace($ghPath)) {
    throw 'GitHub CLI was not found.'
}

& $ghPath auth status
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub CLI authentication is not valid. Re-authenticate before publishing.'
}

$beforeRemote = @(& git ls-remote $repository refs/heads/main)
if ($LASTEXITCODE -ne 0 -or $beforeRemote.Count -eq 0) {
    throw 'The GitHub Pages main branch could not be reached.'
}
$beforeHash = ($beforeRemote[0] -split '\s+')[0]

Push-Location $blogRoot
try {
    & $hexoCmd deploy
    if ($LASTEXITCODE -ne 0) {
        throw "Hexo deploy failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$afterRemote = @(& git ls-remote $repository refs/heads/main)
if ($LASTEXITCODE -ne 0 -or $afterRemote.Count -eq 0) {
    throw 'Deploy completed locally, but the remote main branch could not be verified.'
}
$afterHash = ($afterRemote[0] -split '\s+')[0]

Write-Host ''
Write-Host 'Approved deployment completed.' -ForegroundColor Green
Write-Host "Remote main before: $beforeHash"
Write-Host "Remote main after:  $afterHash"
Write-Host 'Verify the Pages build at https://lukadoncicy77.github.io/'
